# typed: strict
# frozen_string_literal: true

# Internal component for scaffold_generator.
module HakumiORM
  # Internal class for HakumiORM.
  class ScaffoldGenerator
    extend T::Sig

    sig { params(table_name: String, config: Configuration).void }
    def initialize(table_name, config)
      @table_name = T.let(table_name, String)
      singular = singularize(table_name)
      @singular = T.let(singular, String)
      cls = singular.split("_").map(&:capitalize).join
      mod = config.module_name
      @module_name = T.let(mod, T.nilable(String))
      @qualified_cls = T.let(mod ? "#{mod}::#{cls}" : cls, String)
      @qualified_record = T.let("#{@qualified_cls}Record", String)
      @ind = T.let(mod ? "  " : "", String)
      @models_dir = T.let(config.models_dir, T.nilable(String))
      @contracts_dir = T.let(config.contracts_dir, T.nilable(String))
    end

    sig { returns(T::Array[String]) }
    def run!
      created = T.let([], T::Array[String])

      md = @models_dir
      created.concat(scaffold_model(md)) if md

      cd = @contracts_dir
      created.concat(scaffold_contract(cd)) if cd

      created
    end

    private

    sig { params(dir: String).returns(T::Array[String]) }
    def scaffold_model(dir)
      FileUtils.mkdir_p(dir)
      path = File.join(dir, "#{@singular}.rb")
      return [] if File.exist?(path)

      content = +"# typed: strict\n# frozen_string_literal: true\n\n"
      content << "module #{@module_name}\n" if @module_name
      content << "#{@ind}class #{@qualified_cls} < #{@qualified_record}\n"
      content << "#{@ind}end\n"
      content << "end\n" if @module_name
      File.write(path, content)
      [path]
    end

    sig { params(dir: String).returns(T::Array[String]) }
    def scaffold_contract(dir)
      FileUtils.mkdir_p(dir)
      path = File.join(dir, "#{@singular}_contract.rb")
      return [] if File.exist?(path)

      content = +"# typed: strict\n# frozen_string_literal: true\n\n"
      content << "module #{@module_name}\n" if @module_name
      content << "#{@ind}class #{@qualified_record}::Contract < #{@qualified_record}::BaseContract\n"
      content << "#{@ind}  extend T::Sig\n"
      content << "#{@ind}end\n"
      content << "end\n" if @module_name
      File.write(path, content)
      [path]
    end

    sig { params(word: String).returns(String) }
    def singularize(word)
      return "#{word.delete_suffix("ies")}y" if word.end_with?("ies")
      return "#{word.delete_suffix("ves")}f" if word.end_with?("ves")
      return word.delete_suffix("es") if word.end_with?("ses", "xes", "zes", "ches", "shes")
      return word.delete_suffix("s") if word.end_with?("s") && !word.end_with?("ss", "us", "is")

      word
    end
  end
end
