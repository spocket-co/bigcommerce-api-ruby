RSpec.describe Bigcommerce::Config do
  describe '#api_url' do
    let(:config) do
      described_class.new(store_hash: 'abc123').tap do |c|
        c.api_version = api_version unless api_version == :unset
      end
    end

    around(:each) do |example|
      original = ENV['BC_API_ENDPOINT']
      ENV.delete('BC_API_ENDPOINT')
      example.run
      ENV['BC_API_ENDPOINT'] = original
    end

    context 'when auth is legacy' do
      let(:api_version) { :unset }

      it 'returns the configured url' do
        config = described_class.new(auth: 'legacy', url: 'http://foobar.com')
        expect(config.api_url).to eq('http://foobar.com')
      end
    end

    context 'when api_version is unset' do
      let(:api_version) { :unset }

      it 'defaults to v3/catalog' do
        expect(config.api_url).to eq('https://api.bigcommerce.com/stores/abc123/v3/catalog')
      end
    end

    context 'when api_version is nil' do
      let(:api_version) { nil }

      it 'defaults to v3/catalog' do
        expect(config.api_url).to eq('https://api.bigcommerce.com/stores/abc123/v3/catalog')
      end
    end

    context 'when api_version is an empty string' do
      let(:api_version) { '' }

      it 'defaults to v3/catalog' do
        expect(config.api_url).to eq('https://api.bigcommerce.com/stores/abc123/v3/catalog')
      end
    end

    context 'when api_version is whitespace only' do
      let(:api_version) { '   ' }

      it 'defaults to v3/catalog' do
        expect(config.api_url).to eq('https://api.bigcommerce.com/stores/abc123/v3/catalog')
      end
    end

    context 'when api_version is a normal value' do
      let(:api_version) { 'v2' }

      it 'uses the provided version' do
        expect(config.api_url).to eq('https://api.bigcommerce.com/stores/abc123/v2')
      end
    end

    context 'when BC_API_ENDPOINT is set' do
      let(:api_version) { :unset }

      it 'uses the custom endpoint as the base' do
        ENV['BC_API_ENDPOINT'] = 'https://custom.example.com'
        expect(config.api_url).to eq('https://custom.example.com/stores/abc123/v3/catalog')
      end
    end
  end
end
