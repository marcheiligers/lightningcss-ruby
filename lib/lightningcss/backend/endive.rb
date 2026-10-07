# frozen_string_literal: true

module LightningCSS
  module Backend
    module Endive
      RESULT_SIZE = 12
      WASM_PATH = File.expand_path("../../../rust/target/wasm32-wasip1/release/lightningcss_ffi.wasm", __dir__)

      ERROR_CLASSES = {
        1 => ParseError,
        2 => OptionError,
        3 => BundleError,
        4 => Error,
      }.freeze

      ERROR_MESSAGES = {
        "No such file or directory (os error 44)" => "No such file or directory (os error 2)",
      }.freeze

      java_import "run.endive.runtime.ImportValues"
      java_import "run.endive.runtime.Instance"
      java_import "run.endive.wasi.WasiOptions"
      java_import "run.endive.wasi.WasiPreview1"
      java_import "run.endive.wasm.Parser"

      begin
        java_import "org.lightningcss.wasm.LightningCssModule"
      rescue NameError
        # The source-build interpreter remains available when no compiled machine is packaged.
      end

      class Runtime
        def initialize(directory: nil)
          options = WasiOptions.builder
          options.with_directory(directory, java.io.File.new(directory).to_path) if directory

          @wasi = WasiPreview1.builder.with_options(options.build).build
          imports = ImportValues.builder.with_functions(@wasi.to_host_functions.to_a).build
          compiled_module = Endive.compiled_module
          builder = Instance.builder(compiled_module ? compiled_module.wasm_module : Endive.wasm_module)
          builder.with_machine_factory(compiled_module.machine_factory) if compiled_module

          @instance = builder.with_import_values(imports).build
          @memory = @instance.memory
          @mutex = Mutex.new
        end

        def close
          @instance.close
          @wasi.close
        end

        def call(name, input, options)
          @mutex.synchronize do
            result_pointer = allocate(RESULT_SIZE)
            input_pointer, input_size = write_string(input)
            options_pointer, options_size = write_string(options)
            called = false

            function(name).apply(result_pointer, input_pointer, options_pointer)
            called = true

            unwrap(result_pointer)
          ensure
            function("lightningcss_result_free").apply(result_pointer) if called
            deallocate(result_pointer, RESULT_SIZE) if result_pointer
            deallocate(input_pointer, input_size) if input_pointer
            deallocate(options_pointer, options_size) if options_pointer
          end
        end

        def string(name)
          @mutex.synchronize do
            pointer = function(name).apply[0].to_i

            raise Error, "Lightning CSS returned no result" if pointer.zero?

            @memory.readCString(pointer)
          ensure
            function("lightningcss_string_free").apply(pointer) if pointer&.nonzero?
          end
        end

        private

        def function(name)
          @instance.export(name)
        end

        def allocate(size)
          function("lightningcss_allocate").apply(size)[0].to_i
        end

        def deallocate(pointer, size)
          function("lightningcss_deallocate").apply(pointer, size)
        end

        def write_string(value)
          raise ArgumentError, "string contains null byte" if value.include?("\0")

          bytes = "#{value}\0".b.to_java_bytes
          pointer = allocate(bytes.length)
          @memory.write(pointer, bytes)

          [pointer, bytes.length]
        end

        def unwrap(result_pointer)
          value_pointer = @memory.read_int(result_pointer)
          error_pointer = @memory.read_int(result_pointer + 4)
          code = @memory.read_int(result_pointer + 8)

          if error_pointer.nonzero?
            message = @memory.readCString(error_pointer)

            raise ERROR_CLASSES.fetch(code, Error), ERROR_MESSAGES.fetch(message, message)
          end

          raise Error, "Lightning CSS returned no result" if value_pointer.zero?

          @memory.readCString(value_pointer)
        end
      end

      module_function

      def transform(code, options)
        runtime.call("lightningcss_transform", code, options)
      end

      def transform_style_attribute(code, options)
        runtime.call("lightningcss_transform_style_attribute", code, options)
      end

      def bundle(path, options)
        directory = File.dirname(File.expand_path(path))
        bundle_runtime = Runtime.new(directory: directory)

        bundle_runtime.call("lightningcss_bundle", File.expand_path(path), options)
      ensure
        bundle_runtime&.close
      end

      def version
        runtime.string("lightningcss_version")
      end

      def lightningcss_version
        runtime.string("lightningcss_lightningcss_version")
      end

      def runtime
        @runtime ||= Runtime.new
      end

      def compiled?
        !compiled_module.nil?
      end

      def compiled_module
        return unless const_defined?(:LightningCssModule, false)

        @compiled_module ||= LightningCssModule.new
      end

      def wasm_module
        @wasm_module ||= begin
          raise LoadError, "Lightning CSS WebAssembly module not found at #{WASM_PATH}" unless File.file?(WASM_PATH)

          Parser.parse(java.io.File.new(WASM_PATH))
        end
      end
    end

    class << self
      def transform(code, options)
        Endive.transform(code, options)
      end

      def transform_style_attribute(code, options)
        Endive.transform_style_attribute(code, options)
      end

      def bundle(path, options)
        Endive.bundle(path, options)
      end

      def version
        Endive.version
      end

      def lightningcss_version
        Endive.lightningcss_version
      end
    end
  end
end
