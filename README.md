# csv_migration
The gem for flexible parsing CSV files for migration data to DB. For example, you can have an old project with a very complex data structure. 
Or you can't make export data to another format (XML, JSON). You can create a CSV file easily with all the data needed for migration to a new system. 
And create settings for parser for save data to a new DB.

## Installation

The recommended installation method is via Rubygems.
```
gem install csv_migration
```

## Usage:
You should create a new class and then inherit it from the CsvMigration class.

For example:
```ruby
class MyParser < CsvMigration
    def initialize
      super(file_name: 'my_data.csv')
    
      # Relation of header name from the file with a specific field name of a table
      @ref_csv_head_from_file = {
        'email client' => {
          field: :client_email,
          require: true,
          validate: :email_validate,
          callback: :email_lowercase
          },
        'score' => {
          field: :score,
          require: true
        },
        'review' => {
          field: :description
        },
        'surname' => {
          field: :full_name,
          require: true,
          prefix: 'first name'
        }
      }
    
      # Dictionary with fields names from the @ref_csv_head_from_file where need to search duplicates
      @duplicates_dict = %i[]

      # Dictionary for replace a key word to a value word: 'hallo' => 'Hello'
      @replace_dict = {}
    end
    
    # Create new record in the DB
    #
    # @param [Hash] record in specific hash format
    def add_record_to_db(record)
      # Search data of model if is necessary
      client = User.find_by(email: record[:client_email])
    
      if client.nil?
        # Save error to array @not_saved_records
        save_error(record, "Client wasn't found in the DB by email")
        return
      end
    
      data = {
        client_id: client.id,
        score: record[:score],
        review: record[:description],
        full_name: record[:full_name]
      }
    
      # Save or update rating data to the DB 
      rating = update_or_create_data(data)
    
      if rating.nil?
        save_error(record, "Record has not been created!")
        puts "Error. Record has not been created!"
    
        return
      end
    
      puts "Record successfully created/updated with id: #{rating.id}"
    end
end
```

In the constructor you should call **super** with a file name: 
```
super(file_name: 'my_data.csv')
```

You can specify the second param is delimiter
```ruby
super(file_name: 'my_data.csv', delimiter: ';')
```
By default: **delimiter** = ';'

Then you should specify relation in @ref_csv_head_from_file (hash variable): 
```ruby
@ref_csv_head_from_file = {
    'email client' => {
      field: :client_email,
      require: true,
      validate: :email_validate,
      callback: :email_lowercase
    },
    'score' => {
      field: :score,
      require: true
    },
    'review' => {
      field: :description
    },
    'surname' => {
      field: :full_name,
      require: true,
      prefix: 'first name'
    }
}
```
Keys of hash - it's header name of columns in a CSV file

Example CSV file:
```
email client;name;score;review;surname
aaa@aa.aa;Alex;70;Goog man;Snow
```

In every hash of a key, you can use the next symbols:  
**require:** a field should not be empty (true/false). For true will generate an error if the field is empty  
**replace:** need to use @replace_dict ( @replace_dict = { 'what need replace' => 'replace to this' } ) (true/false)  
**prefix:** need to add value as a prefix from a field header name (header name from CSV file) (string)  
**validate:** callback method which necessary call for validating a specific format (symbol)  
**is_empty:** array with fields where need to search data if a value is empty (field name from CSV file header) (array of strings)  
**default:** a value which need set by default in any case (any type)  
**callback:** callback method which necessary call for creating a specific format (symbol)  


**@duplicates_dict** - array of fields (symbols) where need to search duplicates  
For example we can set this:  
```ruby
@duplicates_dict = %i[client_email full_name]
```
Then the parser will remove all found duplicates from @parsed_data and will write to a file with duplicates 

**@replace_dict** - hash for replace a key word to a value word: 'hallo' => 'Hello'. For use translation by dictionary you should set 
```
replace: true
```
for a specific field  
For example we can set this:  
```ruby
@replace_dict = {
  'bus transport' => 'car',
  'Dr. Mister' => 'Sir.'
}
```

You can use own **callback methods** for validation data. A method should return false/nil for incorrect data.  
By default you can use **email_validate** method for a validation email address.  
```ruby
# Callback for validating specific format data
#
# @param [String] value data for validate
def email_validate(value)
  check = value.match?(/\A[\w+\-.]+@[a-z\d\-.]+\.[a-z]+\z/i)

  puts "Email Error #{value}" unless check

  check
end
```

You can use own **callback methods** for creating a specific format of data.  
By default you can use **email_lowercase** method for a transfer email address to lower case.
```ruby
# Callback for lowercase data
#
# @param [String] value Data from the CSV file after all manipulation (replace, prefix, etc)
# @param [String] header_name Header name a the CSV file
# @param [String] prev_value Data from the CSV file before all manipulation (replace, prefix, etc)
# @param [Hash] field_data Settings for a specific field from @ref_csv_head_from_file
def email_lowercase(value:, header_name:, prev_value:, field_data:)
  value.downcase
end
```

In the method add_record_to_db(record) you can get every record from @parsed_data
```ruby
# Create new record in the DB
#
# @param [Hash] record in specific hash format
def add_record_to_db(record)
  # Search data of model if is necessary
  client = User.find_by(email: record[:client_email])

  if client.nil?
    # Save error to array @not_saved_records
    save_error(record, "Client wasn't found in the DB by email")
    return
  end

  data = {
    client_id: client.id,
    score: record[:score],
    review: record[:description],
    full_name: record[:full_name]
  }

  # Save or update rating data to the DB 
  rating = update_or_create_data(data)

  if rating.nil?
    save_error(record, "Record has not been created!")
    puts "Error. Record has not been created!"

    return
  end

  puts "Record successfully created/updated with id: #{rating.id}"
end
```
For save error to a file with errors you can use next method:
```ruby
save_error(record, "My message")
```

If you want get all records then you can use **create_data_to_db** method instead **add_record_to_db(record)**   
```ruby
# Create new data in the DB
def create_data_to_db
  @parsed_data
end
```
@parsed_data - array of hashes with all parsed data. Key **id:** - line number in a CSV file (without header)  

In the finish, the parser will create new files with logs (errors, duplicates, not saved data) and CSV files with correct data (without errors and duplicates).

## Attention
All duplicates will remove from @parsed_data. For example, if parser will find two same emails then these two emails will remove from @parsed_data

## Execution

For start parsing you should call your parser class:
```ruby
parser = MyParser.new
parser.call
```

## History
Versions:

0.0.1 - Add new functional
0.0.2 - Orthographic errors fixed