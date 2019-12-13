require 'minitest/autorun'
require 'csv_migration'

FILE_NAME = 'test.csv'.freeze

class TestParsing < CsvMigration
  def initialize
    super(file_name: FILE_NAME)

    @ref_csv_head_from_file = {
      'user email' => {
        field: :email,
        require: true,
        validate: :email_validate,
        callback: :email_lowercase
      },
      'user name' => {
        field: :full_name,
        require: true
      }
    }
  end

  # Create new data in the DB
  def create_data_to_db
    @parsed_data
  end
end

class TestCsvMigration < Minitest::Test
  def test_call
    header = ['user name', 'user email']
    body = [
      %w[Alex AaA@aAa.aAa],
      %w[Peter BBb@bbB.bbB],
      %w[Max cCC@cCc.cCC]
    ]

    finish = [
      { id: 0, email: 'aaa@aaa.aaa', full_name: 'Alex' },
      { id: 1, email: 'bbb@bbb.bbb', full_name: 'Peter' },
      { id: 2, email: 'ccc@ccc.ccc', full_name: 'Max' }
    ]

    file = File.open(FILE_NAME, 'w')
    file.puts header.join(';')

    body.each { |data| file.puts data.join(';') }

    file.close

    parser = TestParsing.new
    parser.call
    data = parser.create_data_to_db

    assert(data, finish)

    File.delete(FILE_NAME) if File.exist?(FILE_NAME)
    parser.remove_old_files
  end
end
