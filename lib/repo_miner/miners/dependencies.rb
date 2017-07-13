require 'bibliothecary'
require 'pp'

module RepoMiner
  module Miners
    class Dependencies
      def analyse(commit)
        all_paths = blob_paths(commit.commit)

        added_paths = all_paths.select{|path| path[:status] == :added }.map{|path| path[:path] }
        modified_paths = all_paths.select{|path| path[:status] == :modified }.map{|path| path[:path] }
        removed_paths = all_paths.select{|path| path[:status] == :deleted }.map{|path| path[:path] }

        added_manifest_paths = Bibliothecary.identify_manifests(added_paths)
        modified_manifest_paths = Bibliothecary.identify_manifests(modified_paths)
        removed_manifest_paths = Bibliothecary.identify_manifests(removed_paths)

        # don't both analysing commits where no dependency files touched
        return nil if added_manifest_paths.empty? && modified_manifest_paths.empty? && removed_manifest_paths.empty?

        # Added manifest files
        added_manifests = []
        added_manifest_paths.each do |manifest_path|
          path = commit.commit.tree.path(manifest_path)
          blob = commit.repository.repository.lookup(path[:oid])
          manifest = Bibliothecary.analyse_file(manifest_path, blob.content)

          new_manifest = manifest.first

          if new_manifest
            dependencies = new_manifest[:dependencies]
            added = dependencies.map{|d| d[:name] }

            added.map! do |dep_name|
              dep = dependencies.find{|d| d[:name] == dep_name }
              {
                name: dep_name,
                requirement: dep[:requirement],
                type: dep[:type]
              }
            end

            added_manifests << {
              path: manifest_path,
              platform: manifest[0][:platform],
              added_dependencies: added,
              modified_dependencies: [],
              removed_dependencies: []
            }
          end
        end

        # Modified manifest files
        modified_manifests = []
        modified_manifest_paths.each do |manifest_path|
          before_path = commit.commit.parents[0].tree.path(manifest_path)
          before_blob = commit.repository.repository.lookup(before_path[:oid])
          before_manifest = Bibliothecary.analyse_file(manifest_path, before_blob.content)

          before_modified_manifest = before_manifest.first

          after_path = commit.commit.tree.path(manifest_path)
          after_blob = commit.repository.repository.lookup(after_path[:oid])
          after_manifest = Bibliothecary.analyse_file(manifest_path, after_blob.content)

          after_modified_manifest = after_manifest.first

          if before_modified_manifest && after_modified_manifest
            before_dependencies = before_modified_manifest[:dependencies]
            after_dependencies = after_modified_manifest[:dependencies]

            added_dependency_names = after_dependencies.map{|d| d[:name] } - before_dependencies.map{|d| d[:name] }
            removed_dependency_names = before_dependencies.map{|d| d[:name] } - after_dependencies.map{|d| d[:name] }
            modified_dependency_names = after_dependencies.map{|d| d[:name] } - added_dependency_names - removed_dependency_names

            # added_dependencies
            added_dependencies = added_dependency_names.map do |dep_name|
              dep = after_dependencies.find{|d| d[:name] == dep_name }
              {
                name: dep_name,
                requirement: dep[:requirement],
                type: dep[:type]
              }
            end

            # modified_dependencies
            modified_dependencies = []

            # removed_dependencies
            removed_dependencies = removed_dependency_names.map do |dep_name|
              dep = before_dependencies.find{|d| d[:name] == dep_name }
              {
                name: dep_name,
                requirement: dep[:requirement],
                type: dep[:type]
              }
            end

            modified_manifests << {
              path: manifest_path,
              platform: after_modified_manifest[:platform],
              added_dependencies: added_dependencies,
              modified_dependencies: modified_dependencies,
              removed_dependencies: removed_dependencies
            }
          end
        end

        # Removed manifest files
        removed_manifests = []
        removed_manifest_paths.each do |manifest_path|
          path = commit.commit.parents[0].tree.path(manifest_path)
          blob = commit.repository.repository.lookup(path[:oid])
          manifest = Bibliothecary.analyse_file(manifest_path, blob.content)

          removed_manifest = manifest.first

          if removed_manifest
            dependencies = removed_manifest[:dependencies]
            removed = dependencies.map{|d| d[:name] }

            removed.map! do |dep_name|
              dep = dependencies.find{|d| d[:name] == dep_name }
              {
                name: dep_name,
                requirement: dep[:requirement],
                type: dep[:type]
              }
            end

            removed_manifests << {
              path: manifest_path,
              platform: manifest[0][:platform],
              added_dependencies: [],
              modified_dependencies: [],
              removed_dependencies: removed
            }
          end
        end

        data = {
          added_manifests: added_manifests,
          modified_manifests: modified_manifests,
          removed_manifests: removed_manifests
        }

        commit.add_data(:dependencies, data)
      end

      def blob_paths(commit)
        paths = []

        if commit.parents.count == 0 # initial commit
          commit.tree.walk_blobs(:postorder) do |root, entry|
            paths << {
              status: :added,
              path: "#{root}#{entry[:name]}"
            }
          end
        else
          diffs = commit.parents[0].diff(commit)

          diffs.each_delta do |delta|
            paths << {
              status: delta.status,
              path: delta.new_file[:path]
            }
          end
        end
        paths
      end
    end
  end
end
