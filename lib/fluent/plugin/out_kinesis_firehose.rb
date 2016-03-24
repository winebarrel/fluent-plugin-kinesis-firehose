require "fluent_plugin_kinesis_firehose/version"

class Fluent::KinesisFirehoseOutput < Fluent::BufferedOutput
  Fluent::Plugin.register_output('kinesis_firehose', self)

  include Fluent::SetTimeKeyMixin
  include Fluent::SetTagKeyMixin

  USER_AGENT_SUFFIX = "fluent-plugin-kinesis-firehose/#{FluentPluginKinesisFirehose::VERSION}"
  PUT_RECORDS_MAX_COUNT = 500
  PUT_RECORDS_MAX_DATA_SIZE = 1024 * 1024 * 4

  unless method_defined?(:log)
    define_method('log') { $log }
  end

  config_param :profile,                   :string,  :default => nil
  config_param :credentials_path,          :string,  :default => nil
  config_param :aws_key_id,                :string,  :default => nil, :secret => true
  config_param :aws_sec_key,               :string,  :default => nil, :secret => true
  config_param :region,                    :string,  :default => nil
  config_param :endpoint,                  :string,  :default => nil
  config_param :http_proxy,                :string,  :default => nil
  config_param :delivery_stream_name,      :string
  config_param :data_key,                  :string,  :default => nil
  config_param :append_new_line,           :bool,    :default => true
  config_param :retries_on_putrecordbatch, :integer, :default => 3
  config_param :local_path_fallback,       :string,  :default => nil

  def initialize
    super
    require 'aws-sdk'
    require 'multi_json'
  end

  def configure(conf)
    super
    @sleep_duration = Array.new(@retries_on_putrecordbatch) {|n| ((2 ** n) * scaling_factor) }
  end

  def format(tag, time, record)
    [tag, time, record].to_msgpack
  end

  def write(chunk)
    chunk = chunk.to_enum(:msgpack_each)

    chunk.select {|tag, time, record|
      if not @data_key or record[@data_key]
        true
      else
        log.warn("'#{@data_key}' key does not exist: #{[tag, time, record].inspect}")
        false
      end
    }.map {|tag, time, record|
      convert_record_to_data(record)
    }.each_slice(PUT_RECORDS_MAX_COUNT) {|data_list|
      put_records(data_list)
    }
  rescue => e
    log.error e.message
    log.error_backtrace e.backtrace
  end

  private

  def convert_record_to_data(record)
    if @data_key
      data = record[@data_key].to_s
    else
      data = MultiJson.dump(record)
    end

    if @append_new_line
      data + "\n"
    else
      data
    end
  end

  def put_records(data_list)
    state = 0

    data_list.slice_before {|data|
      data_size = data.size
      state += data_size

      if PUT_RECORDS_MAX_DATA_SIZE < state
        state = data_size
        true
      else
        false
      end
    }.each {|chunk|
      put_record_batch_with_retry(chunk)
    }
  end

  def put_record_batch_with_retry(data_list, retry_count=0)
    records = data_list.map do |data|
      {:data => data}
    end

    response = client.put_record_batch(
      :delivery_stream_name => @delivery_stream_name,
      :records => records
    )

    if response[:failed_put_count] && response[:failed_put_count] > 0
      failed_records = collect_failed_records(data_list, response)

      if retry_count < @retries_on_putrecordbatch
        sleep @sleep_duration[retry_count]
        retry_count += 1
        log.warn 'Retrying to put records. Retry count: %d' % retry_count
        put_record_batch_with_retry(failed_records.map{|record| record[:data] }, retry_count)
      else
        failed_records.each {|record|
          log.error 'Could not put record, Error: %s/%s, Record: %s' % [
            record[:error_code],
            record[:error_message],
            record[:data]
          ]
        }

        if not @local_path_fallback.nil?
          File.open(@local_path_fallback, 'a') { |f|
            failed_records.each { |record| f.write record[:data] }
          }
        end
      end
    end
  end

  def collect_failed_records(data_list, response)
    failed_records = []

    response[:request_responses].each_with_index do |record, index|
      if record[:error_code]
        failed_records.push(
          data: data_list[index],
          error_code: record[:error_code],
          error_message: record[:error_message]
        )
      end
    end

    failed_records
  end

  def client
    return @client if @client

    options = {:user_agent_suffix => USER_AGENT_SUFFIX}
    options[:region] = @region if @region
    options[:endpoint] = @endpoint if @endpoint
    options[:http_proxy] = @http_proxy if @http_proxy

    if @aws_key_id and @aws_sec_key
      options[:access_key_id] = @aws_key_id
      options[:secret_access_key] = @aws_sec_key
    elsif @profile
      credentials_opts = {:profile_name => @profile}
      credentials_opts[:path] = @credentials_path if @credentials_path
      credentials = Aws::SharedCredentials.new(credentials_opts)
      options[:credentials] = credentials
    end

    if @debug
      options[:logger] = Logger.new(log.out)
      options[:log_level] = :debug
      #options[:http_wire_trace] = true
    end

    @client = Aws::Firehose::Client.new(options)
  end

  def scaling_factor
    0.5 + rand * 0.1
  end
end
