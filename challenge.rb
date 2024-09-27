# frozen_string_literal: true

require 'json'
require 'yaml'

# Base class for users and companies
class VerifiedCollection
  attr_accessor :list

  def initialize(file_name)
    json_data = read_file file_name
    @list = verify_data json_data
  end

  def read_file(file_name)
    File.read(file_name)
  rescue StandardError, SystemCallError => e
    puts "Reading the file an error occured. #{e.message}"
  end

  def verify_data(companies)
    SchemaVerifier.verify companies, required_fields
  end
end

# Collect valid User data
class Users < VerifiedCollection
  def initialize
    super 'users.json'
  end

  def required_fields
    {
      id: :integer,
      first_name: :string,
      last_name: :string,
      email: :email,
      company_id: :integer,
      email_status: :boolean,
      active_status: :boolean,
      tokens: :integer
    }
  end
end

# Collect valid Company Data
class Companies < VerifiedCollection
  def initialize
    super 'companies.json'
  end

  def required_fields
    {
      id: :integer,
      name: :string,
      top_up: :integer,
      email_status: :boolean
    }
  end
end

# Verify schema of parsed input data
class SchemaVerifier
  EMAIL_FIELD = /\A[\w+\-.]+@[a-z\d-]+(\.[a-z\d-]+)*\.[a-z]+\z/i
  def self.verify(input, required_fields)
    begin
      parsed_input = JSON.parse(input)
    rescue JSON::ParserError => e
       puts "Invalid JSON format #{e.message}"
    end

    valid_input = parsed_input.select do |record|
      verify_schema(record, required_fields)
    end
    valid_input.empty? ? [] : valid_input
  end

  # Match and verify required fields and value types
  # rubocop:disable Metrics/MethodLength
  def self.verify_schema(record, required_fields)
    required_fields.each do |key, field_type|
      return false unless record.key?(key.to_s)

      val = record[key.to_s]
      case field_type
      when :string
        return false unless val.is_a? String
      when :integer
        return false unless val.is_a? Integer
      when :boolean
        return false unless [true, false].include? val
      when :email
        return false unless val.is_a? String
        return false unless EMAIL_FIELD.match? val
      else
        return false
      end
    end
    true
  end
  # rubocop:enable Metrics/MethodLength
end

# Process output file for companies and their users
class CompanyUsersAndTokens
  def initialize
    @users = Users.new.list
    @companies = Companies.new.list
  end

  def execute
    return false, 'No valid data available' if @users.empty? || @companies.empty?

    puts companies_users.to_yaml
    File.write('output.txt', companies_users.to_yaml)
  end

  # Collect company data for output
  def companies_users
    @companies.map do |company|
      emailed_users, not_emailed_users, top_ups = company_users company
      {
        "Company Id": company['id'],
        "Company Name": company['name'],
        "Users Emailed": format_users(emailed_users),
        "Users Not Emailed": format_users(not_emailed_users),
        "Total amount of top ups for #{company['name']}": top_ups
      }.transform_keys(&:to_s)
    end
  end

  # Format user data
  def format_users(users)
    sorted_users = users.sort_by { |user| user['last_name'] }
    sorted_users.map do |user|
      {
        "#{user['last_name']}, #{user['first_name']}, #{user['email']}": [
          "Previous Token Balance, #{user['tokens']}",
          "New Token Balance', #{user['new_tokens']}"
        ]
      }.transform_keys(&:to_s)
    end
  end

  # Find associated users by company and collect totals for topups
  def company_users(company)
    emailed_users = []
    not_emailed_users = []
    top_ups = 0
    @users.each do |user|
      next unless user['company_id'] == company['id'] && user['active_status']

      user['new_tokens'] = user['tokens'] + company['top_up']
      emailed_users.append user if user['email_status']
      not_emailed_users.append user unless user['email_status']
      top_ups += company['top_up']
    end
    [emailed_users, not_emailed_users, top_ups]
  end
end

CompanyUsersAndTokens.new.execute
