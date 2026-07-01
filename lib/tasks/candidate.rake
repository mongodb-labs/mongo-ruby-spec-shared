# frozen_string_literal: true

require_relative '../mrss/release/candidate'

namespace :candidate do
  desc 'Initialize a new product.yml file'
  task :init do
    Mrss::Release::ProductData.init!
    puts "product.yml file created"
  end

  desc 'Print the release notes for the next candidate release'
  task :preview do
    Mrss::Release::Candidate.instance do |candidate|
      # load the pending changes before bumping the version, since it
      # depends on the value of the current version.
      candidate.pending_changes
      candidate.bump_version
      puts candidate.release_notes
    end
  end

  desc 'List the pull requests to be included in the next release'
  task :prs do
    Mrss::Release::Candidate.instance.decorated_prs.each do |pr|
      print "\##{pr['number']}[#{pr['type-code']}] "
      print "#{pr['jira']} " if pr['jira']
      puts pr['short-title']
    end
  end

  desc 'Create a new branch and pull request for the candidate'
  task create: :check_branch_status do
    Mrss::Release::Candidate.instance do |candidate|
      origin = `git config get remote.origin.url`
      match = origin.match(/:(.*?)\//) or raise "origin url is not in expected format: #{origin.inspect}"
      user = match[1]

      if candidate.rc_branch?
        puts 'already in an RC branch -- skipping checkout'
      else
        candidate.bump_version
        if candidate.branch_exists?
          puts 'RC branch already exists -- resuming from existing branch'
          sh 'git', 'checkout', candidate.branch_name
        else
          puts 'bumping version and creating RC branch...'
          sh 'git', 'checkout', '-b', candidate.branch_name
          candidate.save_version!
        end
      end

      if candidate.uncommitted_changes?
        sh 'git', 'commit', '-am', "Bump version to #{candidate.product.version}"
      else
        puts 'no uncommitted changes -- no commit step necessary'
      end

      sh 'git', 'push', 'origin', candidate.branch_name

      if candidate.pull_request_exists?(user, candidate.branch_name)
        puts "pull request already exists for #{user}:#{candidate.branch_name}"
      else
        puts 'writing release notes to /tmp/pr-body.md...'
        File.write('/tmp/pr-body.md', candidate.release_notes)

        sh 'gh', 'pr', 'create',
             '--head', "#{user}:#{candidate.branch_name}",
             '--base', candidate.product.base_branch,
             '--title', "Release candidate for #{candidate.product.version}",
             '--label', 'release-candidate',
             '--body-file', '/tmp/pr-body.md'
      end
    end
  end

  # Ensures the current branch is up-to-date with no uncommitted changes
  task :check_branch_status do
    unless ENV['SKIP_STATUS_CHECK']
      sh 'git pull >/dev/null', verbose: false
      changes = `git status --short --untracked-files=no`.strip
      abort "There are uncommitted changes. Commit (or revert) the changes and try again." if changes.length > 0
    end
  end
end
