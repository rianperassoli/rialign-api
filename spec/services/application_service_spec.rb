require "rails_helper"

RSpec.describe ApplicationService, type: :service do
  # A throwaway subclass exercising the base helpers.
  let(:service_class) do
    Class.new(described_class) do
      def initialize(mode:)
        @mode = mode
      end

      def call
        case @mode
        when :ok      then success({ value: 42 })
        when :string  then failure("boom")
        when :array   then failure(%w[a b])
        when :errors  then failure(User.new.tap(&:valid?).errors)
        end
      end
    end
  end

  it ".call instantiates and calls" do
    result = service_class.call(mode: :ok)
    expect(result).to be_success
    expect(result).not_to be_failure
    expect(result.data).to eq(value: 42)
    expect(result.errors).to eq([])
  end

  it "wraps a string error" do
    result = service_class.call(mode: :string)
    expect(result).to be_failure
    expect(result.errors).to eq(["boom"])
  end

  it "wraps an array of errors" do
    expect(service_class.call(mode: :array).errors).to eq(%w[a b])
  end

  it "extracts full_messages from ActiveModel::Errors" do
    result = service_class.call(mode: :errors)
    expect(result).to be_failure
    expect(result.errors).to include(a_string_matching(/can't be blank/i))
  end
end
