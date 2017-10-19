require 'spec_helper'
require 'nokogiri'

RSpec.describe "Correctly creates junit xml" do
  EXAMPLE_DIR = File.expand_path("../../example", __FILE__)
  BIN = File.expand_path("../../bin/solano_rspec_runner", __FILE__)

  before(:all) do
    ENV['REPORTS_DIRECTORY'] = 'reports'
    ENV['REPORT_PATTERN'] = '%s-rspec.xml'
    ENV['REPORT_ID'] = 'self-test'
  end

  before(:each) do
    FileUtils.rm_f(SolanoRspecRunner.get_report_path_info.first)
  end

  let(:spec_files) { "" }
  let(:report_file) { SolanoRspecRunner.get_report_path_info.first }
  let(:rpsec_command) { system("cd #{EXAMPLE_DIR}; #{BIN} #{spec_files}") }
  let(:junit_doc) { File.open(File.join(EXAMPLE_DIR, report_file)) { |f| Nokogiri::XML(f) } }
  let(:testsuite) { junit_doc.xpath("//testsuite").first }
  let(:command_property) { junit_doc.xpath("//testsuite/properties/property[@name='command']").first}
  let(:testcases) { junit_doc.xpath("/testsuite/testcase") }
  let(:passing_testcases) { junit_doc.xpath("/testsuite/testcase[count(*)=0]") } # testcase has no child elements
  let(:pending_testcases) { junit_doc.xpath("/testsuite/testcase[skipped]") }
  let(:failed_testcases) { junit_doc.xpath("/testsuite/testcase[failure]") }
  let(:errored_testcases) { junit_doc.xpath("/testsuite/testcase[error]") }
  let(:first_failed_testcase_content) { junit_doc.xpath("/testsuite/testcase[failure]").first.content }
  let(:first_errored_testcase_error) { junit_doc.xpath("/testsuite/testcase/error").first }

  context "with only passing tests" do
    let(:spec_files) { "spec/pass_1_spec.rb spec/pass_2_spec.rb" }

    it "returned the correct exit code" do
      expect(rpsec_command).to eq(true)
    end

    it "testsuite has accurate counts" do
      expect(testsuite['tests']).to eql("2")
      expect(testsuite['skipped']).to eql("0")
      expect(testsuite['failures']).to eql("0")
      expect(testsuite['errors']).to eql("0")
    end

    it "the executed command included all test files" do
      expect(command_property['value']).to include(spec_files)
    end

    it "the correct number of testcases" do
      expect(testcases.count).to eql(2)
      expect(passing_testcases.count).to eql(2)
      expect(pending_testcases.count).to eql(0)
      expect(failed_testcases.count).to eql(0)
      expect(errored_testcases.count).to eql(0)
    end
  end

  context "with only failing tests" do
    let(:spec_files) { "spec/fail_1_spec.rb spec/fail_2_spec.rb" }

    it "returned the correct exit code" do
      expect(rpsec_command).to eq(false)
    end

    it "testsuite has accurate counts" do
      expect(testsuite['tests']).to eql("2")
      expect(testsuite['skipped']).to eql("0")
      expect(testsuite['failures']).to eql("2")
      expect(testsuite['errors']).to eql("0")
    end

    it "the executed command included all test files" do
      expect(command_property['value']).to include(spec_files)
    end

    it "the correct number of testcases" do
      expect(testcases.count).to eql(2)
      expect(passing_testcases.count).to eql(0)
      expect(pending_testcases.count).to eql(0)
      expect(failed_testcases.count).to eql(2)
      expect(errored_testcases.count).to eql(0)
    end

    it "include the error message in failed testcase" do
      expect(first_failed_testcase_content).to include("expected true")
      expect(first_failed_testcase_content).to include("got false")
    end
  end

  context "with only skipped tests" do
    let(:spec_files) { "spec/skip_1_spec.rb spec/skip_2_spec.rb" }

    it "returned the correct exit code" do
      expect(rpsec_command).to eq(true)
    end

    it "testsuite has accurate counts" do
      expect(testsuite['tests']).to eql("2")
      expect(testsuite['skipped']).to eql("2")
      expect(testsuite['failures']).to eql("0")
      expect(testsuite['errors']).to eql("0")
    end

    it "the executed command included all test files" do
      expect(command_property['value']).to include(spec_files)
    end

    it "the correct number of testcases" do
      expect(testcases.count).to eql(2)
      expect(passing_testcases.count).to eql(0)
      expect(pending_testcases.count).to eql(2)
      expect(failed_testcases.count).to eql(0)
      expect(errored_testcases.count).to eql(0)
    end
  end

  context "with passing, failing, and skipped tests" do
    let(:spec_files) { "spec/pass_1_spec.rb spec/fail_1_spec.rb spec/skip_1_spec.rb spec/pass_2_spec.rb spec/fail_2_spec.rb spec/skip_2_spec.rb" }

    it "returned the correct exit code" do
      expect(rpsec_command).to eq(false)
    end

    it "testsuite has accurate counts" do
      expect(testsuite['tests']).to eql("6")
      expect(testsuite['skipped']).to eql("2")
      expect(testsuite['failures']).to eql("2")
      expect(testsuite['errors']).to eql("0")
    end

    it "the executed command included all test files" do
      expect(command_property['value']).to include(spec_files)
    end

    it "the correct number of testcases" do
      expect(testcases.count).to eql(6)
      expect(passing_testcases.count).to eql(2)
      expect(pending_testcases.count).to eql(2)
      expect(failed_testcases.count).to eql(2)
      expect(errored_testcases.count).to eql(0)
    end

    it "include the error message in failed testcase" do
      expect(first_failed_testcase_content).to include("expected true")
      expect(first_failed_testcase_content).to include("got false")
    end
  end

  context "with only a syntax error test" do
    let(:spec_files) { "spec/syntax_error_spec.rb" }

    it "returned the correct exit code" do
      expect(rpsec_command).to eq(false)
    end

    it "testsuite has accurate counts" do
      expect(testsuite['tests']).to eql("1")
      expect(testsuite['skipped']).to eql("0")
      expect(testsuite['failures']).to eql("0")
      expect(testsuite['errors']).to eql("1")
    end

    it "the executed command included all test files" do
      expect(command_property['value']).to include(spec_files)
    end

    it "the correct number of testcases" do
      expect(testcases.count).to eql(1)
      expect(passing_testcases.count).to eql(0)
      expect(pending_testcases.count).to eql(0)
      expect(failed_testcases.count).to eql(0)
      expect(errored_testcases.count).to eql(1)
    end

    it "include the error message in errored testcase" do
      expect(first_errored_testcase_error['message']).to eql("ERROR: Marked as error due to rspec command failure")
    end
  end

  context "with syntax error and passing tests" do
    let(:spec_files) { "spec/syntax_error_spec.rb spec/pass_1_spec.rb" }

    it "returned the correct exit code" do
      expect(rpsec_command).to eq(false)
    end

    it "testsuite has accurate counts" do
      expect(testsuite['tests']).to eql("2")
      expect(testsuite['skipped']).to eql("0")
      expect(testsuite['failures']).to eql("0")
      expect(testsuite['errors']).to eql("2")
    end

    it "the executed command included all test files" do
      expect(command_property['value']).to include(spec_files)
    end

    it "the correct number of testcases" do
      expect(testcases.count).to eql(2)
      expect(passing_testcases.count).to eql(0)
      expect(pending_testcases.count).to eql(0)
      expect(failed_testcases.count).to eql(0)
      expect(errored_testcases.count).to eql(2)
    end

    it "include the error message in errored testcase" do
      expect(first_errored_testcase_error['message']).to eql("ERROR: Marked as error due to rspec command failure")
    end
  end

  context "with syntax error and skipping tests" do
    let(:spec_files) { "spec/syntax_error_spec.rb spec/skip_1_spec.rb" }

    it "returned the correct exit code" do
      expect(rpsec_command).to eq(false)
    end

    it "testsuite has accurate counts" do
      expect(testsuite['tests']).to eql("2")
      expect(testsuite['skipped']).to eql("0")
      expect(testsuite['failures']).to eql("0")
      expect(testsuite['errors']).to eql("2")
    end

    it "the executed command included all test files" do
      expect(command_property['value']).to include(spec_files)
    end

    it "the correct number of testcases" do
      expect(testcases.count).to eql(2)
      expect(passing_testcases.count).to eql(0)
      expect(pending_testcases.count).to eql(0)
      expect(failed_testcases.count).to eql(0)
      expect(errored_testcases.count).to eql(2)
    end

    it "include the error message in errored testcase" do
      expect(first_errored_testcase_error['message']).to eql("ERROR: Marked as error due to rspec command failure")
    end
  end

  context "with only an undefined variable test" do
    let(:spec_files) { "spec/undefined_var_spec.rb" }

    it "returned the correct exit code" do
      expect(rpsec_command).to eq(false)
    end

    it "testsuite has accurate counts" do
      expect(testsuite['tests']).to eql("1")
      expect(testsuite['skipped']).to eql("0")
      expect(testsuite['failures']).to eql("1")
      expect(testsuite['errors']).to eql("0")
    end

    it "the executed command included all test files" do
      expect(command_property['value']).to include(spec_files)
    end

    it "the correct number of testcases" do
      expect(testcases.count).to eql(1)
      expect(passing_testcases.count).to eql(0)
      expect(pending_testcases.count).to eql(0)
      expect(failed_testcases.count).to eql(1)
      expect(errored_testcases.count).to eql(0)
    end

    it "include the error message in failed testcase" do
      expect(first_failed_testcase_content).to include("undefined local variable or method")
    end
  end

  context "with undefined variable and passing tests" do
    let(:spec_files) { "spec/undefined_var_spec.rb spec/pass_1_spec.rb" }

    it "returned the correct exit code" do
      expect(rpsec_command).to eq(false)
    end

    it "testsuite has accurate counts" do
      expect(testsuite['tests']).to eql("2")
      expect(testsuite['skipped']).to eql("0")
      expect(testsuite['failures']).to eql("1")
      expect(testsuite['errors']).to eql("0")
    end

    it "the executed command included all test files" do
      expect(command_property['value']).to include(spec_files)
    end

    it "the correct number of testcases" do
      expect(testcases.count).to eql(2)
      expect(passing_testcases.count).to eql(1)
      expect(pending_testcases.count).to eql(0)
      expect(failed_testcases.count).to eql(1)
      expect(errored_testcases.count).to eql(0)
    end

    it "include the error message in failed testcase" do
      expect(first_failed_testcase_content).to include("undefined local variable or method")
    end
  end

  context "with undefined variable and skipped tests" do
    let(:spec_files) { "spec/undefined_var_spec.rb spec/skip_1_spec.rb" }

    it "returned the correct exit code" do
      expect(rpsec_command).to eq(false)
    end

    it "testsuite has accurate counts" do
      expect(testsuite['tests']).to eql("2")
      expect(testsuite['skipped']).to eql("1")
      expect(testsuite['failures']).to eql("1")
      expect(testsuite['errors']).to eql("0")
    end

    it "the executed command included all test files" do
      expect(command_property['value']).to include(spec_files)
    end

    it "the correct number of testcases" do
      expect(testcases.count).to eql(2)
      expect(passing_testcases.count).to eql(0)
      expect(pending_testcases.count).to eql(1)
      expect(failed_testcases.count).to eql(1)
      expect(errored_testcases.count).to eql(0)
    end

    it "include the error message in failed testcase" do
      expect(first_failed_testcase_content).to include("undefined local variable or method")
    end
  end

  context "with only an uninitialized constant test" do
    let(:spec_files) { "spec/uninitialized_constant_spec.rb" }

    it "returned the correct exit code" do
      expect(rpsec_command).to eq(false)
    end

    it "testsuite has accurate counts" do
      expect(testsuite['tests']).to eql("1")
      expect(testsuite['skipped']).to eql("0")
      expect(testsuite['failures']).to eql("1")
      expect(testsuite['errors']).to eql("0")
    end

    it "the executed command included all test files" do
      expect(command_property['value']).to include(spec_files)
    end

    it "the correct number of testcases" do
      expect(testcases.count).to eql(1)
      expect(passing_testcases.count).to eql(0)
      expect(pending_testcases.count).to eql(0)
      expect(failed_testcases.count).to eql(1)
      expect(errored_testcases.count).to eql(0)
    end

    it "include the error message in failed testcase" do
      expect(first_failed_testcase_content).to include("uninitialized constant NonExistingClass")
    end
  end

  context "with uninitialized constant and passing tests" do
    let(:spec_files) { "spec/uninitialized_constant_spec.rb spec/pass_1_spec.rb" }

    it "returned the correct exit code" do
      expect(rpsec_command).to eq(false)
    end

    it "testsuite has accurate counts" do
      expect(testsuite['tests']).to eql("2")
      expect(testsuite['skipped']).to eql("0")
      expect(testsuite['failures']).to eql("1")
      expect(testsuite['errors']).to eql("0")
    end

    it "the executed command included all test files" do
      expect(command_property['value']).to include(spec_files)
    end

    it "the correct number of testcases" do
      expect(testcases.count).to eql(2)
      expect(passing_testcases.count).to eql(1)
      expect(pending_testcases.count).to eql(0)
      expect(failed_testcases.count).to eql(1)
      expect(errored_testcases.count).to eql(0)
    end

    it "include the error message in failed testcase" do
      expect(first_failed_testcase_content).to include("uninitialized constant NonExistingClass")
    end
  end
end
