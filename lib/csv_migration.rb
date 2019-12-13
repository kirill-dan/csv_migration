# frozen_string_literal: true

# Description: Parse and test data from a csv file.
class CsvMigration
  # @param [String] file_name with extension (my_file.csv)
  # @param [String] delimiter for parsing, by default = ';'
  def initialize(file_name:, delimiter: ';')
    # File name for parsing in csv format
    @file_name_csv = file_name
    @delimiter = delimiter

    @file_name = @file_name_csv.split('.csv').first

    # File for export correct data from the base file
    @correct_file_data_csv = File.expand_path("v_parser_correct_#{@file_name}.csv")
    @errors_log = File.expand_path("v_parser_errors_#{@file_name}.log")
    @duplicates_log = File.expand_path("v_parser_duplicates_#{@file_name}.log")
    @not_saved_file_data_errors = File.expand_path("v_parser_not_saved_#{@file_name}.log")

    # Parsing file
    @file_for_parsing = File.expand_path(@file_name_csv)

    # Remove old files
    remove_old_files

    # Count rows in the file without header
    @count_file_lines = `wc -l #{@file_for_parsing}`.split[0].to_i - 1

    @line_num = 0
    @counter_good_records = 0
    @counter_duplicates = 0

    # Raw data from a file without header
    @file_raw_data = []

    # Data after parsing
    @parsed_data = []

    # Header fields from csv file
    @parsing_file_header = []

    # Error statuses
    @errors = {}

    # Errors data
    @errors_data = {}

    # Duplicates records
    @duplicates = {}

    # Errors creating records from the file
    @not_saved_records = []

    # Relation of header name from the file with a specific field name of a table
    #
    # Key: column name in the csv file
    # Value:
    #         field: a field name of a table in a DB (symbol)
    #         require: a field should not be empty (true/false)
    #         replace: need to use @replace_dict ( @replace_dict = { 'what need replace' => 'replace to this' } ) (true/false)
    #         prefix: need to add value as a prefix from a field header name (header name from CSV file) (string)
    #         validate: callback method which necessary call for validating a specific format (symbol)
    #         is_empty: array with fields where need to search data if a value is empty (field name from CSV file header) (array of strings)
    #         default: a value which need set by default in any case (any type)
    #         callback: callback method which necessary call for creating a specific format (symbol)
    @ref_csv_head_from_file = {}

    # Dictionary with fields names from the @ref_csv_head_from_file where need to search duplicates
    @duplicates_dict = %i[]

    # Dictionary for replace a key word to a value word: 'hallo' => 'Hello'
    @replace_dict = {}
  end

  # Start parsing
  def call
    puts "Start parse file #{@file_for_parsing}"

    # Read line from csv file
    File.foreach(@file_for_parsing) do |line|
      data = line.encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '').chomp.split(@delimiter).map(&:strip)

      if @line_num.zero?
        @parsing_file_header = data.map(&:downcase)
        @line_num += 1
        next
      end

      @file_raw_data << line.encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '').chomp

      check = check_require_fields(data)

      unless check[:status]
        @line_num += 1
        puts "Incorrect data! Required field: #{check[:error]} is empty!"
        next
      end

      records = find_data_from_csv(data, @ref_csv_head_from_file)

      @parsed_data << { id: @line_num - 1 }.merge(records)

      puts "Parse left #{@count_file_lines - @line_num} lines"
      @line_num += 1
      @counter_good_records += 1
    end

    duplicates_id_list = check_duplicates
    remove_duplicates(duplicates_id_list) if duplicates_id_list.any?

    save_errors

    create_file_without_errors

    double_duplicates = @counter_good_records + @errors.values.sum + @counter_duplicates - @line_num - 1

    puts
    puts "Testing data was finished. All records in the file (without header): #{@line_num - 1}"
    puts "Good records: #{@counter_good_records}"
    puts "Bad records: #{@errors.values.sum}"
    puts "Duplicate records: #{@counter_duplicates}"
    puts "Duplicates more than one field: #{double_duplicates}" if double_duplicates.positive?
    puts "Successfully parsed records: #{@parsed_data.size}"

    error_actions if !@errors.values.sum.zero? || !@counter_duplicates.zero?

    create_data_to_db

    save_record_errors_to_file if @not_saved_records.any?
  end

  # Remove old files
  def remove_old_files
    File.delete(@errors_log) if File.exist?(@errors_log)
    File.delete(@duplicates_log) if File.exist?(@duplicates_log)
    File.delete(@correct_file_data_csv) if File.exist?(@correct_file_data_csv)
    File.delete(@not_saved_file_data_errors) if File.exist?(@not_saved_file_data_errors)
  end

  private

  # Checking variable on is nil or on is empty
  #
  # @param [Any] var variable for check
  def blank?(var)
    var.nil? || var.empty?
  end

  # Checking variable on if exist
  #
  # @param [Any] var variable for check
  def present?(var)
    !blank?(var)
  end

  # Question action before saving data if exist errors
  def error_actions
    print 'This file has errors. Do you want to save data without errors Y/n: '
    respond = STDIN.gets.chomp

    error_actions unless respond.casecmp('y').zero? || respond.casecmp('n').zero? || blank?(respond)
    exit if respond.casecmp('n').zero?
  end

  # Callback for lowercase data
  #
  # @param [String] value Data from the CSV file after all manipulation (replace, prefix, etc)
  # @param [String] header_name Header name a the CSV file
  # @param [String] prev_value Data from the CSV file before all manipulation (replace, prefix, etc)
  # @param [Hash] field_data Settings for a specific field from @ref_csv_head_from_file
  def email_lowercase(value:, header_name:, prev_value:, field_data:)
    value.downcase
  end

  # Callback for validating specific format data
  #
  # @param [String] value data for validate
  def email_validate(value)
    check = value.match?(/\A[\w+\-.]+@[a-z\d\-.]+\.[a-z]+\z/i)

    puts "Email Error #{value}" unless check

    check
  end

  # Check fields which should be present
  #
  # @param [Array] data list of values
  def check_require_fields(data)
    @ref_csv_head_from_file.each do |key, value|
      return { error: value[:field], status: false } unless check_field(data, key.downcase, value)
    end

    { status: true }
  end

  # Checking specific field which should be present
  #
  # @param [Array] data list of values from a file
  # @param [String] key header field name in a file
  # @param [Object] value hash data from dict
  def check_field(data, key, value)
    if @parsing_file_header.find_index(key).nil?
      puts "Please, correct settings in the @ref_csv_head_from_file hash. Key #{key} has not been found in the header of #{@file_name_csv} file!"
      exit
    end

    if value[:require] && blank?(data[@parsing_file_header.find_index(key)])
      check = check_is_empty_field(key, data, value)

      return true if check && validate_field(data_value: check, value: value)

      @errors[value[:field]] = @errors[value[:field]].nil? ? 1 : @errors[value[:field]] + 1
      @errors_data[value[:field]] = [] unless present?(@errors_data[value[:field]])
      @errors_data[value[:field]] << [data.join(';')]

      return false
    end

    unless validate_field(data_value: data[@parsing_file_header.find_index(key)], value: value)
      @errors[value[:field]] = @errors[value[:field]].nil? ? 1 : @errors[value[:field]] + 1
      @errors_data[value[:field]] = [] unless present?(@errors_data[value[:field]])
      @errors_data[value[:field]] << [data.join(';')]

      return false
    end

    true
  end

  # Validate field if exist validation callback
  #
  # @param [String] data_value value from file
  # @param [Hash] value hash data from dict
  def validate_field(data_value:, value:)

    return true unless present?(value[:validate])

    return method(value[:validate].to_sym).call(data_value) if respond_to?(value[:validate], true)

    true
  end

  # Check all fields on is empty
  #
  # @param [String] key searched key
  # @param [Array] data list with data from file
  # @param [Hash] field Hash data from dict
  def check_is_empty_field(key, data, field)
    return false unless present?(field[:is_empty])

    find_value_in_other_fields(key, data, field)
  end

  # Find value in other fields which was set for search
  #
  # @param [String] key searched key
  # @param [Array] data list with data from file
  # @param [Hash] field Hash data from dict
  def find_value_in_other_fields(key, data, field)
    return data[@parsing_file_header.find_index(key)] unless blank?(data[@parsing_file_header.find_index(key)])

    return false unless field[:is_empty]

    field[:is_empty].each do |value|
      return data[@parsing_file_header.find_index(value.downcase)] unless blank?(data[@parsing_file_header.find_index(value.downcase)])
    end

    false
  end

  # Find data from a CSV file
  #
  # @param [Array] data from file (read one line)
  # @param [Hash] object_dict hash dict for creating data in specific format
  def find_data_from_csv(data, object_dict)
    new_data = {}
    object_dict.each do |key, value|
      field_name = value[:field]

      prev_field_data = present?(new_data[field_name]) ? new_data[field_name] : nil

      new_data[field_name] = find_value_in_other_fields(key.downcase, data, value) if value[:require]
      new_data[field_name] = data[@parsing_file_header.find_index(key.downcase)]&.strip unless value[:require]

      if value[:prefix]
        prefix_value = data[@parsing_file_header.find_index(value[:prefix])]&.strip
        new_data[field_name] = prefix_value + ' ' + new_data[field_name] unless blank?(prefix_value)
      end

      new_data[field_name] = value[:default] if value[:default]
      new_data[field_name] = value[:set_is_empty] if blank?(new_data[field_name]) && value.key?(:set_is_empty)
      new_data[field_name] = replace_by_dict(new_data[field_name]) if value[:replace]

      if value[:callback] && respond_to?(value[:callback], true)
        new_data[field_name] = method(value[:callback].to_sym)
                                 .call(value: new_data[field_name], header_name: key.downcase, prev_value: prev_field_data, field_data: value)
      end
    end

    new_data
  end

  # Replace text by dict @replace_dict
  def replace_by_dict(string)
    @replace_dict.each do |key, value|
      next if blank?(string)
      return value if key.casecmp(string).zero?
    end

    string
  end

  # Search all duplicate records and saving it to a log file
  def check_duplicates
    return [] if @parsed_data.size.zero? || @duplicates_dict.size.zero?

    id_list = []

    puts 'Start search duplicates...'

    @parsed_data.each do |row|
      id = row[:id]
      line = row.clone

      @duplicates_dict.each do |duplicate|
        next unless present?(line[duplicate])

        unless @duplicates.key?(line[duplicate])
          @duplicates = @duplicates.deep_merge(line[duplicate] => { id: [], field: duplicate, value: line[duplicate], data: [] })
        end

        @duplicates[line[duplicate]][:id] << id
        @duplicates[line[duplicate]][:data] << @file_raw_data[id]

        puts "Check line ##{id}"
      end
    end

    @duplicates = @duplicates.select { |_k, v| v[:data].size > 1 && (v[:value] != 'NULL' || blank?(v[:value])) }

    if @duplicates.any?
      file_duplicate = File.open(@duplicates_log, 'w')
      file_duplicate.puts @parsing_file_header.join(';')

      @duplicates.each do |_key, value|
        @counter_duplicates += value[:data].size

        file_duplicate.puts
        file_duplicate.puts "Duplicate field: #{value[:field]}, value: #{value[:value]}"
        file_duplicate.puts
        value[:data].each do |record|
          file_duplicate.puts record
        end

        id_list << value[:id]
      end

      file_duplicate.close
    end

    id_list.flatten.uniq
  end

  # Remove duplicate records from parsed data
  #
  # @param [Array] id_list list duplicates
  def remove_duplicates(id_list)
    @counter_good_records -= id_list.size

    @parsed_data = @parsed_data.reject { |value| id_list.include?(value[:id]) }
  end

  # Save errors data to a log file
  def save_errors
    errors = lambda do |errors_data|
      file_error = File.open(@errors_log, 'w')
      file_error.puts @parsing_file_header.join(';') unless errors_data.size.zero?

      errors_data.each do |key, value|
        file_error.puts
        file_error.puts ' ' * 10 + "#{key.capitalize}:"
        file_error.puts
        value.each do |data|
          file_error.puts data
        end
      end

      file_error.close
    end

    errors.call(@errors_data) if @errors_data.any?

    puts
    puts "Errors: #{@errors}" if @errors.any?
    puts
  end

  # Create new csv export file without errors and duplicates
  def create_file_without_errors
    file_export = File.open(@correct_file_data_csv, 'w')
    file_export.puts @parsing_file_header.join(';')

    @parsed_data.each do |value|
      file_export.puts @file_raw_data[value[:id]]
    end

    file_export.close
  end

  # Add found error to errors data
  #
  # @param [Hash] record parsed data
  # @param [String] error_text message for error
  def save_error(record, error_text)
    @not_saved_records << {
      raw: @file_raw_data[record[:id]],
      data: record,
      error: error_text
    }

    puts error_text
  end

  # Create new data in the DB
  # This method get @parsed_data and call in loop create_data_to_db method
  def create_data_to_db
    @parsed_data.each do |record|
      add_record_to_db(record)
    end

    show_finished_test
  end

  # Show text in the console after migration
  def show_finished_test
    puts
    puts 'Migration was finished.'
    puts "Total records for insert: #{@parsed_data.size}"
    puts "Saved records: #{@parsed_data.size - @not_saved_records.size}"
    puts "Not saved records: #{@not_saved_records.size}. See log with errors: #{@not_saved_file_data_errors}"
  end

  # Create new record in the DB
  #
  # @param [Hash] _record in specific hash format
  def add_record_to_db(_record)
    raise 'You should make realization callback method add_record_to_db(record)'

    # Search data of model if is necessary
    # user = User.find_by(email: record[:email].downcase)
    #
    # if user.nil?
    #   save_error(record, "User has not been found in the DB by email")
    #   next
    # end
  end

  # Save all records with errors to a file
  def save_record_errors_to_file
    errors = lambda do |errors_data|
      file_error = File.open(@not_saved_file_data_errors, 'w')

      errors_data.each do |value|
        file_error.puts value
      end

      file_error.close
    end

    errors.call(@not_saved_records) if @not_saved_records.any?
  end
end
