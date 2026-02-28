# typed: strict
# frozen_string_literal: true

# Internal component for migration/file_generator.
module HakumiORM
  class Migration
    # Internal module for HakumiORM.
    module FileGenerator
      extend T::Sig

      VALID_NAME_PATTERN = T.let(/\A[a-z]\w*\z/, Regexp)

      sig { params(name: String, path: String, now: Time).returns(String) }
      def self.generate(name:, path:, now: Time.now)
        validate_name!(name)
        FileUtils.mkdir_p(path)

        existing = Dir.children(path).select { |f| f.end_with?("_#{name}.rb") }
        raise HakumiORM::Error, "Migration '#{name}' already exists: #{existing.first}" unless existing.empty?

        timestamp = next_timestamp(path, now: now)
        filename = "#{timestamp}_#{name}.rb"
        class_name = name.split("_").map(&:capitalize).join

        content = <<~RUBY
          # typed: false
          # frozen_string_literal: true

          class #{class_name} < HakumiORM::Migration
            def up
            end

            def down
            end
          end
        RUBY

        filepath = File.join(path, filename)
        File.write(filepath, content)
        filepath
      end

      sig { params(path: String, now: Time).returns(String) }
      def self.next_timestamp(path, now:)
        candidate = now.strftime("%Y%m%d%H%M%S")
        max_existing = Dir.children(path)
                          .grep(/\A\d{14}_/)
                          .map { |f| f[0, 14] }
                          .max

        candidate = (Time.strptime(max_existing, "%Y%m%d%H%M%S") + 1).strftime("%Y%m%d%H%M%S") if max_existing && max_existing >= candidate

        candidate
      end

      sig { params(name: String).void }
      private_class_method def self.validate_name!(name)
        return if VALID_NAME_PATTERN.match?(name)

        if name.match?(/\A\d/)
          raise HakumiORM::Error,
                "Migration name '#{name}' must start with a letter (e.g., 'create_users')"
        end
        raise HakumiORM::Error,
              "Migration name '#{name}' must contain only lowercase letters, digits, and underscores (e.g., 'create_users')"
      end

      private_class_method :next_timestamp
    end
  end
end
