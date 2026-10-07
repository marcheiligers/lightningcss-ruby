# frozen_string_literal: true

require "test_helper"

module LightningCSS
  class EndiveBackendTest < Minitest::Spec
    test "uses JRuby's bundled Endive runtime" do
      skip "JRuby-only backend" unless RUBY_ENGINE == "jruby"

      assert defined?(Backend::Endive)
      assert_equal ".a{color:red}", LightningCSS.minify(".a { color: #ff0000 }")
    end

    test "uses a build-time compiled machine when one is available" do
      skip "JRuby-only backend" unless RUBY_ENGINE == "jruby"
      skip "compiled machine is not on the classpath" unless Backend::Endive.const_defined?(:LightningCssModule, false)

      assert_predicate Backend::Endive, :compiled?
      assert_equal ".a{color:red}", LightningCSS.minify(".a { color: #ff0000 }")
    end
  end
end
