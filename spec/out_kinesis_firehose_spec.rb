describe Fluent::KinesisFirehoseOutput do
  let(:time) do
    Time.parse('2015-09-01 01:23:45 UTC').to_i
  end

  let(:default_fluentd_conf) do
    <<-EOS
      type kinesis_firehose
      delivery_stream_name DeliveryStreamName
    EOS
  end

  let(:additional_fluentd_conf) { '' }

  let(:fluentd_conf) do
    default_fluentd_conf + additional_fluentd_conf
  end

  let(:driver) do
    Fluent::Test::OutputTestDriver.new(Fluent::KinesisFirehoseOutput, 'test.default').configure(fluentd_conf)
  end

  let(:client) do
    Aws::Firehose::Client.new(stub_responses: true)
  end

  let(:log) do
    driver.instance.log
  end

  before do
    allow(driver.instance).to receive(:client) { client }
  end

  context 'without retry' do
    before do
      expect(log).to_not receive(:error)
    end

    context 'when events is sent' do
      specify do
        expect(client).to receive(:put_record_batch).with(
          :delivery_stream_name=>"DeliveryStreamName",
           :records=>
            [{:data=>%!{"key1":"foo","key2":100}\n!},
             {:data=>%!{"key1":"bar","key2":200}\n!}]
        ).and_return({})

        driver.run do
          driver.emit({'key1' => 'foo', 'key2' => 100}, time)
          driver.emit({'key1' => 'bar', 'key2' => 200}, time)
        end
      end
    end

    context 'when events is sent without append_new_line' do
      let(:additional_fluentd_conf) { 'append_new_line false' }

      specify do
        expect(client).to receive(:put_record_batch).with(
          :delivery_stream_name=>"DeliveryStreamName",
           :records=>
            [{:data=>'{"key1":"foo","key2":100}'},
             {:data=>'{"key1":"bar","key2":200}'}]
        ).and_return({})

        driver.run do
          driver.emit({'key1' => 'foo', 'key2' => 100}, time)
          driver.emit({'key1' => 'bar', 'key2' => 200}, time)
        end
      end
    end

    context 'when events is sent with data_key' do
      let(:additional_fluentd_conf) { 'data_key data' }

      specify do
        expect(client).to receive(:put_record_batch).with(
          :delivery_stream_name=>"DeliveryStreamName",
           :records=>
            [{:data=>"foo\n"},
             {:data=>"200\n"}]
        ).and_return({})

        driver.run do
          driver.emit({'data' => 'foo', 'key2' => 100}, time)
          driver.emit({'key1' => 'bar', 'data' => 200}, time)
        end
      end
    end

    context 'when events is sent without data_key' do
      let(:additional_fluentd_conf) { 'data_key data' }

      specify do
        expect(client).to_not receive(:put_record_batch)
        expect(log).to receive(:warn).with(%!'data' key does not exist: ["test.default", 1441070625, {"key1"=>"foo", "key2"=>100}]!)
        expect(log).to receive(:warn).with(%!'data' key does not exist: ["test.default", 1441070625, {"key1"=>"bar", "key2"=>200}]!)

        driver.run do
          driver.emit({'key1' => 'foo', 'key2' => 100}, time)
          driver.emit({'key1' => 'bar', 'key2' => 200}, time)
        end
      end
    end
  end

  context 'when events is sent with retry' do
    let(:response) do
      {
        failed_put_count: 1,
        request_responses: [
          {error_code: 'ERROR1', error_message: 'MESSAGE1'},
          {error_code: 'ERROR2', error_message: 'MESSAGE2'}
        ]
      }
    end

    context 'when retry success' do
      specify do
        expect(client).to receive(:put_record_batch).with(
          :delivery_stream_name=>"DeliveryStreamName",
           :records=>
            [{:data=>%!{"key1":"foo","key2":100}\n!},
             {:data=>%!{"key1":"bar","key2":200}\n!}]
        ).and_return(response)

        expect(client).to receive(:put_record_batch).with(
          :delivery_stream_name=>"DeliveryStreamName",
           :records=>
            [{:data=>%!{"key1":"foo","key2":100}\n!},
             {:data=>%!{"key1":"bar","key2":200}\n!}]
        ).and_return({})

        expect(log).to receive(:warn).with('Retrying to put records. Retry count: 1')
        expect(log).to_not receive(:error)

        driver.run do
          driver.emit({'key1' => 'foo', 'key2' => 100}, time)
          driver.emit({'key1' => 'bar', 'key2' => 200}, time)
        end
      end
    end

    context 'when retry failed' do
      let(:additional_fluentd_conf) do
        'retries_on_putrecordbatch 0'
      end

      specify do
        expect(client).to receive(:put_record_batch).with(
          :delivery_stream_name=>"DeliveryStreamName",
           :records=>
            [{:data=>%!{"key1":"foo","key2":100}\n!},
             {:data=>%!{"key1":"bar","key2":200}\n!}]
        ).and_return(response)

        expect(log).to_not receive(:warn)
        expect(log).to receive(:error).with(%!Could not put record, Error: ERROR1/MESSAGE1, Record: {"key1":"foo","key2":100}\n!)
        expect(log).to receive(:error).with(%!Could not put record, Error: ERROR2/MESSAGE2, Record: {"key1":"bar","key2":200}\n!)

        driver.run do
          driver.emit({'key1' => 'foo', 'key2' => 100}, time)
          driver.emit({'key1' => 'bar', 'key2' => 200}, time)
        end
      end
    end
  end
end
