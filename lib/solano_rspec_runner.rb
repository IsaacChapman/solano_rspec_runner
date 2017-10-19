require 'pathname'
require 'fileutils'
require 'open3'
require 'nokogiri'
require 'tempfile'
require 'socket'
require 'time'

module SolanoRspecRunner
  class << self
    def run(argv)

      # Ensure test file arguments were supplied
      if argv.length == 0 then
        $stderr.puts "ERROR: No test files listed as arguments"
        $stderr.puts "Usage: #{$PROGRAM_NAME} test_file [test_file ...]"
        Kernel.exit(1)
      end

      # Ensure arguments are files
      @test_files = []
      for i in 0 ... argv.length
        pn = Pathname.new(argv[i])
        if pn.file? then
          @test_files << argv[i]
        else
          $stderr.puts "ERROR: '#{argv[i]}' does not exist"
        end
      end
      if @test_files.count != argv.count then
        $stderr.puts "ERROR: One or more 'test_file' arguments is invalid"
        $stderr.puts "Usage: #{$PROGRAM_NAME} test_file [test_file ...]"
        Kernel.exit(2)
      end

      # Where is the final Junit XML report stored?
      xml_report_file, xml_reports_directory, xml_report_pattern, xml_report_id = get_report_path_info

      # Solano can alter the '.rspec' file in the repo's root directory
      rspec_arguments = ENV['RSPEC_ARGS'] || '--order defined --backtrace --color --tty'

      # Use a temp file for the initially generated Junit XML file to ensure tests are marked as error if something goes wrong
      xml_report_temp_file = Tempfile.new(xml_report_id).path

      # Run rspec command and capture outputs
      @rspec_command = "rspec #{rspec_arguments} --format RspecJunitFormatter --out #{xml_report_temp_file} "
      # Add test files to command
      @rspec_command << ARGV.join(" ")
      
      Open3.popen3(@rspec_command) do |stdin, stdout, stderr, wait_thr|
        # Rspec writes to stdout and not stderr???
        @rspec_output = stdout.read
        @rspec_status = wait_thr.value.exitstatus
      end

      # Now the fun part...handle different result scenarios...
      # The existence of a non-zero-byte generated Junit XML file indicates rspec didn't insta-fail from a syntax error, undefined method/variable, etc.
      if ! File.size?(xml_report_temp_file).nil? then
        @junit_doc = File.open(xml_report_temp_file) { |f| Nokogiri::XML(f) }
        @tests, @skipped, @failures, @errors = get_test_counts
        @missing_test_files = get_missing_test_files
      else
        $stderr.puts "NOTICE: A valid Junit XML report file was NOT generated"
        @junit_doc = new_junit_xml_doc
        @all_errors = true
        @tests, @skipped, @failures, @errors = [0, 0, 0, 0]
      end

      # If no tests were run and the command failed, presume an rspec level error, so mark all tests as failed
      if @rspec_status != 0 && @tests == 0 then
        @all_errors = true
      end

      if @all_errors then
        # While RspecJunitFormatter does not mark tests as 'error' ever (https://github.com/sj26/rspec_junit_formatter/blob/master/lib/rspec_junit_formatter.rb),
        # marking these tests as 'error' is more accurate (even though Solano may mark them as 'failure')
        @test_files.each do |test_file|
          add_testcase(test_file, 'error', "ERROR: Marked as error due to rspec command failure", ":\n#{@rspec_command}\n\n#{@rspec_output}")
          @tests += 1
          @errors += 1
        end
      else
        @missing_test_files.each do |test_file|
          add_testcase(test_file, 'skipped', "#{test_file} did not report output, marked as skipped")
          @tests += 1
          @skipped += 1
        end
      end

      # Set the test counts
      testsuite_node = @junit_doc.xpath("//testsuite").first
      testsuite_node['tests'] = @tests.to_s
      testsuite_node['skipped'] = @skipped.to_s
      testsuite_node['failures'] = @failures.to_s
      testsuite_node['errors'] = @errors.to_s

      # Insert @rspec_command as property
      rspec_command_property = Nokogiri::XML::Node.new('property', @junit_doc)
      rspec_command_property['name'] = "command"
      rspec_command_property['value'] = @rspec_command
      @junit_doc.xpath("//testsuite/properties").first.add_child(rspec_command_property)

      # Write Junit XML file
      File.write(xml_report_file, @junit_doc.to_xml)
      if ENV.has_key?('TDDIUM_REPO_ROOT') && ENV.has_key?('TDDIUM_SESSION_ID') then
        # Also attach to build artifacts tab when run on Solano CI
        # http://docs.solanolabs.com/Setup/interacting-with-build-environment/#using-a-post-worker-hook
        FileUtils.cp(xml_report_file, File.join(ENV['HOME'], 'results', ENV['TDDIUM_SESSION_ID'], 'session', xml_report_file))
      end
      
      Kernel.exit(@rspec_status)
    end

    def add_testcase(test_file, reason, message, message_extended = '') # reason is 'skipped' or 'error'
      system_out = Nokogiri::XML::Node.new('system-out', @junit_doc) # TODO: Check if 'system_out' is required instead of 'system-out'
      system_out.content = "#{message}#{message_extended}"
      reason_node = Nokogiri::XML::Node.new(reason, @junit_doc)
      reason_node['message'] = message
      testcase = Nokogiri::XML::Node.new('testcase', @junit_doc)
      testcase['classname'] = test_file.gsub(/.rb$/, '').gsub('/', '.') # To make consistent with RspecJunitFormatter
      testcase['file'] = path_prefix_test_file(test_file)
      testcase['time'] = "0"
      testcase['name'] = "#{reason.upcase}: #{test_file}"
      testcase << system_out
      testcase << reason_node
      @junit_doc.xpath("//testsuite").first.add_child(testcase)
    end

    def get_report_path_info
      xml_reports_directory = ENV['REPORTS_DIRECTORY'] || 'reports'
      FileUtils.mkdir_p(xml_reports_directory)
      xml_report_pattern = ENV['REPORT_PATTERN'] || '%s-rspec.xml'
      xml_report_id = if ENV.has_key?('REPORT_ID') then
        ENV['REPORT_ID']
      elsif ENV.has_key?('TDDIUM_TEST_EXEC_ID_LIST') then
        ENV['TDDIUM_TEST_EXEC_ID_LIST'].split(",").first
      elsif ENV.has_key?('TDDIUM_TEST_EXEC_ID') then
        ENV['TDDIUM_TEST_EXEC_ID']
      else
        Time.now.to_f.to_s
      end
      xml_report_file = File.join(xml_reports_directory, sprintf(xml_report_pattern, xml_report_id))
      [xml_report_file, xml_reports_directory, xml_report_pattern, xml_report_id]
    end

    def get_test_counts
      tests = @junit_doc.xpath("//testsuite/@tests").first.value.to_i || 0
      skipped = @junit_doc.xpath("//testsuite/@skipped").first.value.to_i || 0
      failures = @junit_doc.xpath("//testsuite/@failures").first.value.to_i || 0
      errors = @junit_doc.xpath("//testsuite/@errors").first.value.to_i || 0
      [tests, skipped, failures, errors]
    end

    # RspecJunitFormatter prefixes a './' to test file paths
    def path_prefix_test_file(test_file)
      if test_file.slice(0,2) == "./" then
        test_file
      else
        "./#{test_file}"
      end
    end

    def get_missing_test_files
      missing_test_files = []
      @test_files.each do |test_file|
        if ! @junit_doc.xpath("//testsuite/testcase[@file='#{path_prefix_test_file(test_file)}']").any? then
          missing_test_files.push(test_file)
        end
      end
      missing_test_files
    end

    def new_junit_xml_doc
      junit_builder = Nokogiri::XML::Builder.new(:encoding => 'UTF-8') do |xml|
        xml.testsuite("name" => "rspec", "tests" => "0", "skipped" => "0", "failures" => "0", "errors" => "0", "time" => "0", "timestamp" => Time.now.iso8601, "hostname" => Socket.gethostname) do
          xml.proprerties do
            xml.property("name" => "generated_by", "value" => $PROGRAM_NAME)
          end
        end
      end
      junit_builder.doc
    end


  end
end

# Example single passing spec RspecJunitFormatter output
#<?xml version="1.0" encoding="UTF-8"?>
#<testsuite name="rspec" tests="1" skipped="0" failures="0" errors="0" time="0.002264" timestamp="2017-10-18T09:37:04-07:00" hostname="isaac-macbook-pro.local">
#  <properties>
#    <property name="seed" value="27054"/>
#  </properties>
#  <testcase classname="spec.pass_spec" name="example passing spec 1 should succeed" file="./spec/pass_spec.rb" time="0.001027"></testcase>
#</testsuite>

# If no arguments were provided, need to run all of the tests that rspec would normally do.
# Default is 'spec/**/*_spec.rb' according to 'rspec --help'
# Find all files that match this pattern and/or:
# 1. Parse command line arguments for -P,--pattern and --exclude-pattern :(
# 2. Allow overriding default command line args with environment variable :)
#    Default args: '--order defined --backtrace --color --tty'
#       (from '--order defined --backtrace --color --tty --format RspecJunitFormatter --out #{file}')