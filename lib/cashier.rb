#!/usr/bin/env ruby

# Bundler setup
require 'rubygems'
require 'bundler/setup'
Bundler.require(:default)

require 'awesome_print'
require 'base64'
require 'colorize'
require 'json'
require 'tty-prompt'

prompt = TTY::Prompt.new

@config = {
            debts: [],
            expenses: 0.0,
            target_remainder: 0.0,
            pay_frequency: 2,
            paycheck_amt: 0.0
          }

#
# Get Balances
#
total_debt = 0.0

load_dotfile = prompt.yes?("Try to load cached settings from .cashier file?")

if load_dotfile
  begin
    File.read('.cashier') do |file|
      @config = JSON.parse(base64.decode64(file))
    end
  rescue Errno::ENOENT => e
    puts "No .cashier file found. Defaulting to manual input..."
    correct_balances = false
  end
else
  @config = {
              debts: [],
              expenses: 0.0,
              target_remainder: 0.0,
              pay_frequency: 2,
              paycheck_amt: 0.0
            }
end

if ENV['DEBUG']
  puts "Read the following config from disk:"
  ap @config
end

@rent = prompt.ask('What are your mandatory recurring monthly expenses (e.g. rent) $', default: @config[:expenses], convert: :float)
@target = prompt.ask('How much money do you want to have leftover after expenses and payments? $', default: @config[:target_remainder], convert: :float)
@interval = prompt.select("How frequently do you get paid?", default: @config[:pay_frequency]) do |menu|
  menu.choice "Every week", 1
  menu.choice "Every other week", 2
  menu.choice "Twice per month", 3
  menu.choice "Every month", 4
end
@income = prompt.ask('How much money is your paycheck usually for? $', default: @config[:paycheck_amt], convert: :float)

# Write updated values back to @config hash
@config[:expenses] = @rent
@config[:target_remainder] = @target
@config[:pay_frequency] = @interval
@config[:paycheck_amt] = @income

unless @config[:debts].empty?
  puts "Found the following outstanding debts:"
  ap @config[:debts]

  correct_balances = prompt.yes?('Does this look correct?')
end

correct_balances ||= false
puts "Please enter any outstanding debts:".bold unless correct_balances
while !correct_balances
  tmp_debt = {}
  tmp_debt[:creditor] = prompt.ask('What is the name of this creditor?')
  tmp_debt[:apr] = prompt.ask('What is the interest rate you are paying on this debt? [e.g.: 0.049 for 4.9%]', convert: :float)
  tmp_debt[:balance] = prompt.ask('How much is the outstanding balance on this debt? $', default: 0.0, convert: :float)
  tmp_debt[:minimum] = prompt.ask('How much is your minimum monthly payment on this debt? $', default: 0.0, convert: :float)
  tmp_debt[:payment] = nil
  @config[:debts].push tmp_debt
  correct_balances = !prompt.yes?('Add another debt?')
end

@config[:debts].each do |debt|
  total_debt += debt[:balance]
end

puts "Total Debt: #{total_debt.round(2)}".red.bold

#
# Get Available Cash
#
cash = prompt.ask("How much cash do you have on hand this week?", default: @income, convert: :float)

CASH_ON_HAND = if cash.zero?
                 4100.0
               else
                 cash.to_f
               end

pool = CASH_ON_HAND - @target

#
# Sort debts by APR
#
debts = @config[:debts].sort_by { |k| k[:apr] }
@config[:debts].reverse!

#
# Figure out if this paycheck has to cover rent as well as other 1st-of-the-month-type-things
#

# Manual Check
auto_rent = prompt.yes?('Use the auto-rent calculator to subtract rent from this payment (if necessary)?')

if auto_rent
  today = Time.now
  first_of_next_month = Time.new(today.year, (today.month + 1), 1)
  if (first_of_next_month - today) <= 1209600
    puts "Your next paycheck needs rent money! Pay the rent. Removing rent money from available pool...".red
    pool -= @rent
  end
else
  subtract_rent = prompt.yes?('Subtract rent payment?')
  if subtract_rent
    pool -= @rent
  end
end

puts "AVAILABLE CASH: $#{pool.round(2)}".green
puts "\n\n"

#
# Check minimum payments
#
@config[:debts].each do |debt|
  minimum = prompt.ask("Enter any minimum payment due to #{debt[:creditor]} & not yet paid this month", default: debt[:minimum], convert: :float)

  pool -= minimum unless minimum.zero?

  debt[:payment] = debt[:minimum]
end

if pool > 0.0
# Allocate remainder to accounts in order of descending APR
  @config[:debts].each do |debt|
    break if pool <= 0

    if (debt[:balance] - debt[:payment]) <= pool
      puts "LOG: available cash ($#{pool}) is greater than the balance of #{debt[:creditor]} debt (less any planned minimum payments); recommend paying #{debt[:creditor]} the full balance of $#{debt[:balance].round(2)}." if ENV['DEBUG']
      pool -= (debt[:balance] - debt[:payment])
      debt[:payment] = debt[:balance]
    else
      debt[:payment] += pool
      pool = 0.0
    end
  end
else
# Advise to make only minimum payments if there's not enough cash to do more
  puts "Planned debt reduction costs are too high to go beyond minimum payments at this time; make those and move on."
end

# List payments
@config[:debts].each do |debt|
  puts "PAY #{debt[:creditor]}: #{debt[:payment].round(2)}".blue.bold
  total_debt -= debt[:payment]
  debt[:balance] -= debt[:payment]
end

puts "Projected debt after today's payments: $#{total_debt.to_i}".green.bold

# Write balances to file
puts "All done! Writing current state of finances to .cashier.".bold
File.write('.cashier', Base64.encode64(JSON.dump(@config)))
