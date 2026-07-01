# frozen_string_literal: true

require 'mrss/release/candidate'

RSpec.describe Mrss::Release::Candidate do
  subject(:candidate) { described_class.new }

  describe '#pr_type_code (private)' do
    it 'returns "x" for :bcbreak' do
      expect(candidate.send(:pr_type_code, :bcbreak)).to eq('x')
    end

    it 'returns "f" for :feature' do
      expect(candidate.send(:pr_type_code, :feature)).to eq('f')
    end

    it 'returns "b" for :bug' do
      expect(candidate.send(:pr_type_code, :bug)).to eq('b')
    end

    it 'returns "?" for nil' do
      expect(candidate.send(:pr_type_code, nil)).to eq('?')
    end
  end
end
