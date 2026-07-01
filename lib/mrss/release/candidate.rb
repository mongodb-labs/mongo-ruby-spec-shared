# frozen_string_literal: true

require 'json'
require 'open3'

require_relative 'product_data'

module Mrss
  module Release
    class Candidate
      # Release note section titles, by pr type
      SECTION_TITLE = {
        bcbreak: "Breaking Changes",
        feature: "New Features",
        bug: "Bug Fixes",
      }.freeze

      # GitHub labels
      BCBREAK = 'bcbreak'
      FEATURE = 'feature'
      BUG = 'bug'
      PATCH = 'patch'

      def self.instance
        @instance ||= new

        yield @instance if block_given?

        @instance
      end

      def product
        @product ||= ProductData.new
      end

      def peek_version
        product.peek_next_version(release_type)
      end

      def bump_version
        product.bump_version(release_type)
      end

      def bump_version!
        product.bump_version!(release_type)
      end

      def save_version!
        product.save_version!
      end

      def branch_name
        "rc-#{product.version}"
      end

      def current_branch_name
        branch = `git symbolic-ref --short HEAD`.chomp
        branch unless branch.to_s.empty?
      end

      def rc_branch?
        current_branch_name == branch_name
      end

      def branch_exists?(branch=branch_name)
        system('git', 'show-ref', '--verify', '--quiet', "refs/heads/#{branch}")
      end

      def uncommitted_changes?
        !system('git', 'diff-index', '--quiet', 'HEAD', '--')
      end

      def pull_request_exists?(owner, branch)
        head = [ owner, branch ].join(':')
        out, = Open3.capture2('gh', 'pr', 'list', '--head', head, '--state', 'open',
                              '--json', 'number', '--jq', 'length > 0')
        out.to_s.strip == 'true'
      end

      # return a string of commit names since the last release
      def pending_changes
        @changes ||= `git log --pretty=format:"%s" #{commit_range}`
      end

      # return an array of commit SHAs since the last release
      def pending_commit_shas
        @pending_commit_shas ||= `git log --pretty=format:"%H" #{commit_range}`.lines.map(&:chomp)
      end

      # return a list of PR numbers since the last release, determined by
      # asking GitHub which PR each commit belongs to (rather than parsing
      # commit messages, which aren't guaranteed to carry a "(#NNN)" suffix)
      def pending_pr_numbers
        @pending_pr_numbers ||= pending_commit_shas.
          flat_map { |sha| pr_numbers_for_commit(sha) }.
          uniq.
          sort.reverse
      end

      # return a JSON string of PR data
      def pending_pr_dump
        @pending_pr_dump ||= `gh pr list --state all --limit 256 --json number,title,labels,url,body --jq 'map(select([.number] | inside([#{pending_pr_numbers.join(',')}]))) | sort_by(.number)'`
      end

      # return a list of PR data since the last release
      def pending_prs
        @pending_prs ||= JSON.parse(pending_pr_dump)
      end

      # return a list of pending prs with additional attributes (summary,
      # short title, jira issue number).
      def decorated_prs
        @decorated_prs ||= pending_prs.map do |pr|
                             jira_issue, pr_title = split_pr_title(pr)
                             summary = extract_summary(pr)
                             type = pr_type(pr)
                             type_code = pr_type_code(type)
                             patch_flag = pr_patch_flag?(pr)

                             pr.merge('jira' => jira_issue,
                                      'short-title' => pr_title,
                                      'summary' => summary,
                                      'type' => type,
                                      'type-code' => type_code,
                                      'patch' => patch_flag)
                           end
      end

      # return a hash of decorated prs grouped by :bcbreak, :feature, or :bug
      def prs_by_type
        @prs_by_type ||= decorated_prs.group_by { |pr| pr['type'] }
      end

      # returns 'major', 'minor', or 'patch', depending on the presence of
      # (respectively) :bcbreak, :feature, or :bug labels.
      #
      # If the RELEASE environment variable is set, its value will be used
      # directly, ignoring whatever PR labels might exist.
      def release_type
        @release_type ||= if ENV['RELEASE']
                            ENV['RELEASE']
                          elsif prs_by_type[:bcbreak]
                            'major'
                          elsif prs_by_type[:feature] && prs_by_type[:feature].any? { |pr| !pr['patch'] }
                            'minor'
                          else
                            'patch'
                          end
      end

      # returns the generated release notes as a string
      def release_notes
        @release_notes ||= release_notes_intro +
          %i[ bcbreak feature bug ].
            flat_map { |type| release_notes_for_type(type) }.join("\n")
      end

      private

      # the git log revision range covering commits since the last release
      # tag (or the entire history, if no tag exists yet)
      def commit_range
        @commit_range ||= product.tag_exists? ? "#{product.tag_name}.." : ""
      end

      # returns the PR number(s) GitHub associates with the given commit
      # SHA. Raises if the lookup itself fails (auth, rate limit, network);
      # warns and returns an empty array if the commit has no associated PR
      # (e.g. a direct push), since that's a legitimate case, not a failure.
      def pr_numbers_for_commit(sha)
        out, err, status = Open3.capture3(
          'gh', 'api', "repos/{owner}/{repo}/commits/#{sha}/pulls", '--jq', '.[].number'
        )

        raise "gh api lookup failed for commit #{sha}: #{err}" unless status.success?

        numbers = out.split("\n")

        if numbers.empty?
          subject = `git log -1 --pretty=format:%s #{sha}`.chomp
          warn "warning: commit #{sha} (#{subject}) has no associated pull request -- excluding it from the release"
        end

        numbers
      end

      # returns an array of strings, each string representing a single line
      # in the release notes for the PR's of the given type.
      def release_notes_for_type(type)
        return [] unless prs_by_type[type]

        [].tap do |lines|
          lines << "\# #{SECTION_TITLE[type]}"
          lines << ''

          prs = prs_by_type[type]
          summarized, unsummarized = prs.partition { |pr| pr['summary'] }

          summarized.each do |pr|
            header = [ '### ' ]
            header << "[#{pr['jira']}](#{jira_url(pr['jira'])}) " if pr['jira']
            header << "#{pr['short-title']} ([PR](#{pr['url']}))"
            lines << header.join
            lines << ''
            lines << pr['summary']
            lines << ''
          end

          if summarized.any? && unsummarized.any?
            lines << ''
            lines << [ '### Other ', SECTION_TITLE[type] ].join
            lines << ''
          end

          unsummarized.each do |pr|
            line = [ '* ' ]
            line << "[#{pr['jira']}](#{jira_url(pr['jira'])}) " if pr['jira']
            line << "#{pr['short-title']} ([PR](#{pr['url']}))"

            lines << line.join
          end

          lines << ''
        end
      end

      # returns the URL of for the given jira issue
      def jira_url(issue)
        "https://jira.mongodb.org/browse/#{issue}"
      end

      # assumes a pr title in the format of "JIRA-1234 PR Title (#1234)",
      # returns a tuple of [ jira-issue, title ], where jira-issue may be
      # blank (if no jira issue is in the title).
      def split_pr_title(pr)
        title = pr['title'].gsub(/\(#\d+\)/, '').strip

        if title =~ /^(\w+-\d+) (.*)$/
          [ $1, $2 ]
        else
          [ nil, title ]
        end
      end

      # extracts the summary section from the pr and returns it (or returns nil
      # if no summary section is detected)
      def extract_summary(pr)
        summary = []
        accumulating = false
        in_code_block = false
        level = nil

        pr['body'].lines.each do |line|
          if !accumulating
            # a header of any level titled "summary" will begin the summary
            if line =~ /^(\#+)\s+summary\s+$/i
              accumulating = true
              level = $1.length
            end
          else
            # if we encounter a code block, we don't let its contents affect our
            # header-level counting (i.e. we don't want to accidentally end the
            # summary just because there's a comment in a code block)
            in_code_block = !in_code_block if line =~ /^```/

            # a header of any level less than or equal to the summary header's
            # level will end the summary
            break if !in_code_block && line =~ /^\#{1,#{level}}\s+/

            # otherwise, the line is part of the summary
            summary << line
          end
        end

        summary.any? ? summary.join.strip : nil
      end

      # Returns a symbol (:bcbreak, :feature, or :bug) that identifies the
      # type of this PR that would most strongly influence what type of release
      # it requires.
      def pr_type(pr)
        if pr['labels'].any? { |l| l['name'] == BCBREAK }
          :bcbreak
        elsif pr['labels'].any? { |l| l['name'] == FEATURE }
          :feature
        elsif pr['labels'].any? { |l| l['name'] == BUG }
          :bug
        else
          nil
        end
      end

      # `true` if the `patch` label is applied to the PR. This is used to
      # indicate that a "feature" PR should be treated as a patch, for
      # determining the release type only.
      def pr_patch_flag?(pr)
        pr['labels'].any? { |l| l['name'] == PATCH }
      end

      def pr_type_code(type)
        case type
        when :bcbreak then 'x'
        when :feature then 'f'
        when :bug     then 'b'
        else '?'
        end
      end

      def series
        major, minor, = product.version_parts

        case release_type
        when 'minor' then 
          "#{major}.x"
        when 'patch' then
          "#{major}.#{minor}.x"
        end
      end

      # Return a string containing the markdown-formatted intro block for
      # the release notes of this candidate.
      def release_notes_intro
        release_description = case release_type
                              when 'major' then 'major release'
                              when 'minor' then "minor release in the #{series} series"
                              when 'patch' then "patch release in the #{series} series"
                              end

        <<~INTRO
          The MongoDB Ruby team is pleased to announce version #{product.version} of the `#{product.package}` gem - #{product.description}. This is a new #{release_description} of #{product.name}.

          Install this release using [RubyGems](https://rubygems.org/) via the command line as follows: 

          ~~~
          gem install -v #{product.version} #{product.package}
          ~~~

          Or simply add it to your `Gemfile`:

          ~~~
          gem '#{product.package}', '#{product.version}'
          ~~~

          Have any feedback? Click on through to MongoDB's JIRA and [open a new ticket](#{product.jira_project_url}) to let us know what's on your mind 🧠.

        INTRO
      end
    end
  end
end
