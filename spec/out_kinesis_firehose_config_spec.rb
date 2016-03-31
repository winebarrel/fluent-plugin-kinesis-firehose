describe 'Fluent::KinesisFirehoseOutput#configure' do
  let(:fluentd_conf) do
    <<-EOS
      type kinesis_firehose
      delivery_stream_name DeliveryStreamName
    EOS
  end

  let(:driver) do
    Fluent::Test::OutputTestDriver.new(Fluent::KinesisFirehoseOutput, 'test.default')
  end

  before do
    driver.configure(fluentd_conf)
  end

  context 'when default' do
    specify do
      expect(driver.instance.profile).to be_nil
      expect(driver.instance.credentials_path).to be_nil
      expect(driver.instance.aws_key_id).to be_nil
      expect(driver.instance.aws_sec_key).to be_nil
      expect(driver.instance.region).to be_nil
      expect(driver.instance.endpoint).to be_nil
      expect(driver.instance.http_proxy).to be_nil
      expect(driver.instance.delivery_stream_name).to eq 'DeliveryStreamName'
      expect(driver.instance.data_key).to be_nil
      expect(driver.instance.append_new_line).to be_truthy
      expect(driver.instance.retries_on_putrecordbatch).to eq 3
      expect(driver.instance.local_path_fallback).to be_nil
    end
  end

  context 'when not default' do
    let(:fluentd_conf) do
      <<-EOS
        type kinesis_firehose
        delivery_stream_name DeliveryStreamName2
        profile PROFILE
        credentials_path CREDENTIALS_PATH
        aws_key_id AWS_KEY_ID
        aws_sec_key AWS_SEC_KEY
        region REGION
        endpoint ENDPOINT
        http_proxy HTTP_PROXY
        data_key data
        append_new_line false
        retries_on_putrecordbatch 4
        local_path_fallback /path/to/local/file
      EOS
    end

    specify do
      expect(driver.instance.profile).to eq 'PROFILE'
      expect(driver.instance.credentials_path).to eq 'CREDENTIALS_PATH'
      expect(driver.instance.aws_key_id).to eq 'AWS_KEY_ID'
      expect(driver.instance.aws_sec_key).to eq 'AWS_SEC_KEY'
      expect(driver.instance.region).to eq 'REGION'
      expect(driver.instance.endpoint).to eq 'ENDPOINT'
      expect(driver.instance.http_proxy).to eq 'HTTP_PROXY'
      expect(driver.instance.delivery_stream_name).to eq 'DeliveryStreamName2'
      expect(driver.instance.data_key).to eq 'data'
      expect(driver.instance.append_new_line).to be_falsey
      expect(driver.instance.retries_on_putrecordbatch).to eq 4
      expect(driver.instance.local_path_fallback).to eq '/path/to/local/file'
    end
  end
end
