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

  describe '#release_notes_for_type (private)' do
    def pr(jira:, title:, summary: nil)
      {
        'jira' => jira,
        'short-title' => title,
        'summary' => summary,
        'url' => 'https://github.com/org/repo/pull/1',
      }
    end

    def notes_for(prs)
      allow(candidate).to receive(:prs_by_type).and_return(bug: prs)
      candidate.send(:release_notes_for_type, :bug)
    end

    context 'for a summarized PR with a jira issue' do
      it 'puts the title first, then jira and PR links' do
        lines = notes_for([ pr(jira: 'RUBY-1', title: 'Fix the thing', summary: 'Details here') ])
        expect(lines).to include(
          '### Fix the thing ([RUBY-1](https://jira.mongodb.org/browse/RUBY-1) | [PR](https://github.com/org/repo/pull/1))'
        )
      end
    end

    context 'for a summarized PR without a jira issue' do
      it 'puts the title first, then just the PR link' do
        lines = notes_for([ pr(jira: nil, title: 'Fix the thing', summary: 'Details here') ])
        expect(lines).to include('### Fix the thing ([PR](https://github.com/org/repo/pull/1))')
      end
    end

    context 'for an unsummarized PR with a jira issue' do
      it 'puts the title first, then jira and PR links' do
        lines = notes_for([ pr(jira: 'RUBY-2', title: 'Small fix') ])
        expect(lines).to include(
          '* Small fix ([RUBY-2](https://jira.mongodb.org/browse/RUBY-2) | [PR](https://github.com/org/repo/pull/1))'
        )
      end
    end

    context 'for an unsummarized PR without a jira issue' do
      it 'puts the title first, then just the PR link' do
        lines = notes_for([ pr(jira: nil, title: 'Small fix') ])
        expect(lines).to include('* Small fix ([PR](https://github.com/org/repo/pull/1))')
      end
    end
  end

  describe '#pending_pr_numbers' do
    before do
      allow(candidate).to receive(:pending_commit_shas).and_return(shas)
    end

    def gh_result(stdout, success:, stderr: '')
      [ stdout, stderr, instance_double(Process::Status, success?: success) ]
    end

    context 'when a commit has a normal PR association' do
      let(:shas) { %w[aaa111] }

      it 'includes the PR number' do
        allow(Open3).to receive(:capture3).
          with('gh', 'api', 'repos/{owner}/{repo}/commits/aaa111/pulls', '--jq', '.[].number').
          and_return(gh_result("42\n", success: true))

        expect(candidate.pending_pr_numbers).to eq(%w[42])
      end
    end

    context 'when a commit has no "(#NNN)" suffix in its message but does have an associated PR' do
      let(:shas) { %w[bbb222] }

      it 'still includes the PR number' do
        allow(Open3).to receive(:capture3).
          with('gh', 'api', 'repos/{owner}/{repo}/commits/bbb222/pulls', '--jq', '.[].number').
          and_return(gh_result("369\n", success: true))

        expect(candidate.pending_pr_numbers).to eq(%w[369])
      end
    end

    context 'when a commit has no associated PR at all' do
      let(:shas) { %w[ccc333] }

      it 'warns (naming the commit and its subject) and excludes the commit' do
        allow(Open3).to receive(:capture3).
          with('gh', 'api', 'repos/{owner}/{repo}/commits/ccc333/pulls', '--jq', '.[].number').
          and_return(gh_result('', success: true))
        allow(candidate).to receive(:`).and_return("Direct push to master\n")

        expect(candidate).to receive(:warn) do |message|
          expect(message).to include('ccc333')
          expect(message).to include('Direct push to master')
        end
        expect(candidate.pending_pr_numbers).to eq([])
      end
    end

    context 'when two commits are associated with the same PR' do
      let(:shas) { %w[ddd444 eee555] }

      it 'deduplicates the PR number' do
        allow(Open3).to receive(:capture3).
          with('gh', 'api', 'repos/{owner}/{repo}/commits/ddd444/pulls', '--jq', '.[].number').
          and_return(gh_result("99\n", success: true))
        allow(Open3).to receive(:capture3).
          with('gh', 'api', 'repos/{owner}/{repo}/commits/eee555/pulls', '--jq', '.[].number').
          and_return(gh_result("99\n", success: true))

        expect(candidate.pending_pr_numbers).to eq(%w[99])
      end
    end

    context 'when the gh api call fails' do
      let(:shas) { %w[fff666] }

      it 'raises an error identifying the commit' do
        allow(Open3).to receive(:capture3).
          with('gh', 'api', 'repos/{owner}/{repo}/commits/fff666/pulls', '--jq', '.[].number').
          and_return(gh_result('', success: false, stderr: 'HTTP 422'))

        expect { candidate.pending_pr_numbers }.to raise_error(/fff666/)
      end
    end
  end
end
