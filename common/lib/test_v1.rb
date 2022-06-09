require "./dependabot/file_fetchers"
require "./dependabot/file_parsers"
require "./dependabot/update_checkers"
require "./dependabot/file_updaters"
require "./dependabot/pull_request_creator"
require "../../omnibus/lib/dependabot/omnibus"
require "./dependabot/config/file_fetcher"

bitbucket_hostname = "bitbucket.honeywell.com"

credentials = [
    {
      "type" => "git_source",
      "host" => bitbucket_hostname,
      "username" => nil,
      "token" => ARGV[0] || "MDgxMTM5OTE3ODg3Ome8PPtVLU0hnP7ErZTWYs/WXXMH",
      "jira_auth" => "SDQ0MjIzMDpXZWxjb21lQDIwMjE="
    }
]

repo_name = ARGV[1] || "users/h499944/repos/deeptest"
directory = "/"
branch = ARGV[3] || "master"
package_manager = ARGV[2] || "pip"


source = Dependabot::Source.new(
  provider: "bitbucket_server",
  hostname: bitbucket_hostname,
  api_endpoint: "https://bitbucket.honeywell.com/rest/api/1.0/",
  repo: repo_name,
  directory: directory,
  branch: branch,
)

puts "Fetching #{package_manager} dependency files for #{repo_name}"
fetcher = Dependabot::FileFetchers.for_package_manager(package_manager).new(
  source: source,
  credentials: credentials,
)

files = fetcher.files
commit = fetcher.commit

##############################
# Parse the dependency files #
##############################
puts "Parsing dependencies information"
parser = Dependabot::FileParsers.for_package_manager(package_manager).new(
  dependency_files: files,
  source: source,
  credentials: credentials,
)

dependencies = parser.parse

begin
  config = Dependabot::Config::FileFetcher.new(source: source, credentials: credentials)
  cfile = Dependabot::Config::File.parse(config.config_file.content)
  uconfig = cfile.update_config(package_manager)
  iversions = uconfig.ignored_versions_for(dependencies)
rescue
  puts "Config File Not Found"
  iversions = nil
end

dependencies.select(&:top_level?).each do |dep|    
    #########################################
    # Get update details for the dependency #
    #########################################
    if iversions == nil
      checker = Dependabot::UpdateCheckers.for_package_manager(package_manager).new(
        dependency: dep,
        dependency_files: files,
        credentials: credentials,
      )
    else
      checker = Dependabot::UpdateCheckers.for_package_manager(package_manager).new(
        dependency: dep,
        dependency_files: files,
        credentials: credentials,
        ignored_versions: iversions?,
      )
    end
  
    next if checker.up_to_date?
  
    requirements_to_unlock =
      if !checker.requirements_unlocked_or_can_be?
        if checker.can_update?(requirements_to_unlock: :none) then :none
        else :update_not_possible
        end
      elsif checker.can_update?(requirements_to_unlock: :own) then :own
      elsif checker.can_update?(requirements_to_unlock: :all) then :all
      else :update_not_possible
      end
  
    next if requirements_to_unlock == :update_not_possible
  
    updated_deps = checker.updated_dependencies(
      requirements_to_unlock: requirements_to_unlock
    )
  
    #####################################
    # Generate updated dependency files #
    #####################################
    print "  - Updating #{dep.name} (from #{dep.version})…"
    updater = Dependabot::FileUpdaters.for_package_manager(package_manager).new(
      dependencies: updated_deps,
      dependency_files: files,
      credentials: credentials,
    )
  
    updated_files = updater.updated_dependency_files
  
    ########################################
    # Create a pull request for the update #
    ########################################
    assignee = (ENV["PULL_REQUESTS_ASSIGNEE"] || ENV["GITLAB_ASSIGNEE_ID"])&.to_i
    assignees = assignee ? [assignee] : assignee
    pr_creator = Dependabot::PullRequestCreator.new(
      source: source,
      base_commit: commit,
      dependencies: updated_deps,
      files: updated_files,
      credentials: credentials,
      assignees: assignees,
      author_details: { name: "Dependabot", email: "no-reply@github.com" },
      label_language: true,
    )
    pull_request = pr_creator.create
    puts " submitted"
  
    next unless pull_request
  
    # Enable GitLab "merge when pipeline succeeds" feature.
    # Merge requests created and successfully tested will be merge automatically.
    if ENV["GITLAB_AUTO_MERGE"]
      g = Gitlab.client(
        endpoint: source.api_endpoint,
        private_token: ENV["GITLAB_ACCESS_TOKEN"]
      )
      g.accept_merge_request(
        source.repo,
        pull_request.iid,
        merge_when_pipeline_succeeds: true,
        should_remove_source_branch: true
      )
    end
  end
