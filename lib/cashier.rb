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
require 'date'
require 'time'

SECONDS_IN_DAY = 86400

@prompt = TTY::Prompt.new
@total_debt = 0.0

##################
# Helper Methods #
##################

def symbolize_keys(hash)
  result = {}
  hash.each do |k,v|
    result[k.to_sym] = hash[k]
  end

  result
end

def days_in_month(year, month)
  Date.new(year, month, -1).day
end

def rent_calc(pay_interval)
  today = Time.now
  days_in_current_month = days_in_month(today.year, today.month)
  first_of_next_month = Time.new(today.year, (today.month + 1), 1)
  rent_interval_in_seconds = case pay_interval
                             when 1 # weekly
                               SECONDS_IN_DAY * 7
                             when 2 # every other week
                               SECONDS_IN_DAY * 14
                             when 3 # twice monthly
                               ((SECONDS_IN_DAY * days_in_current_month) / 2).to_i
                             when 4 # monthly
                               SECONDS_IN_DAY * days_in_current_month
                             else
                               raise "Something went wrong with rent calculation! (Hit a segment of code we should never have hit; likely cause: invalid selection for paycheck interval)"
                             end

  if (first_of_next_month - today) <= rent_interval_in_seconds
    @prompt.warn "Your next paycheck has to cover rent money! Pay the rent. Removing rent money from available pool..."
    @pool -= @rent
  else
    @prompt.ok "Your next rent payment is more than 1 pay period away; no need to factor it in here!"
  end
end

###########################################
# Get User Configuration (Debts & Income) #
###########################################

load_dotfile = @prompt.yes?("Try to load cached settings from .cashier file?")

if load_dotfile
  begin
    file = File.read('.cashier')
    @config = JSON.parse(Base64.decode64(file))
  rescue Errno::ENOENT => e
    @prompt.warn "No .cashier file found. Defaulting to manual input..."
    correct_balances = false
  end

  unless @config.empty?
    @config = symbolize_keys(@config)
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
  @prompt.warn "Configuration hash:"
  ap @config
end

@rent = @prompt.ask('What is your rent? $', default: @config[:expenses], convert: :float)
@target = @prompt.ask('How much money do you want to have leftover after expenses and payments? $', default: @config[:target_remainder], convert: :float)
@interval = @prompt.select("How frequently do you get paid?", default: @config[:pay_frequency]) do |menu|
  menu.choice "Every week", 1
  menu.choice "Every other week", 2
  menu.choice "Twice per month", 3
  menu.choice "Every month", 4
end
@income = @prompt.ask('How much money is your paycheck usually for? $', default: @config[:paycheck_amt], convert: :float)

# Write updated values back to @config hash
@config[:expenses] = @rent
@config[:target_remainder] = @target
@config[:pay_frequency] = @interval
@config[:paycheck_amt] = @income

unless @config[:debts].empty?
  @prompt.say "Found the following outstanding debts:"
  ap @config[:debts]

  correct_balances = @prompt.yes?('Does this look correct?')
end

correct_balances ||= false
@prompt.say "Please enter any outstanding debts:" unless correct_balances
while !correct_balances
  tmp_debt = {}
  tmp_debt[:creditor] = @prompt.ask('What is the name of this creditor?')
  tmp_debt[:apr] = @prompt.ask('What is the interest rate you are paying on this debt? [e.g.: 0.049 for 4.9%]', convert: :float)
  tmp_debt[:balance] = @prompt.ask('How much is the outstanding balance on this debt? $', default: 0.0, convert: :float)
  tmp_debt[:minimum] = @prompt.ask('How much is your minimum monthly payment on this debt? $', default: 0.0, convert: :float)
  tmp_debt[:payment] = nil
  @config[:debts].push tmp_debt
  correct_balances = !@prompt.yes?('Add another debt?')
end

@config[:debts].each do |debt|
  @total_debt += debt[:balance]
end

puts "Total Debt: #{@total_debt.round(2)}".red.bold

######################
# Get Available Cash #
######################
cash = @prompt.ask("How much cash do you have on hand this week? $", default: @income, convert: :float)

CASH_ON_HAND = cash

@pool = CASH_ON_HAND - @target

#####################
# Sort debts by APR #
#####################
debts = @config[:debts].sort_by { |k| k[:apr] }
@config[:debts].reverse!

#################################################
# Figure out if this paycheck has to cover rent #
#################################################

# Automatic or manual rent checker
auto_rent = @prompt.yes?('Use the auto-rent calculator to subtract rent from this payment (if necessary)?')

if auto_rent
  rent_calc(@interval)
else
  subtract_rent = @prompt.yes?('Subtract rent payment from available cash for debt reduction?')
  if subtract_rent
    @pool -= @rent
  end
end

@prompt.ok "AVAILABLE CASH: $#{@pool.round(2)}"

##########################
# Check minimum payments #
##########################
@config[:debts].each do |debt|
  minimum = @prompt.ask("Enter any minimum payment due to #{debt[:creditor]} & not yet paid this month", default: debt[:minimum], convert: :float)

  @pool -= minimum unless minimum.zero?

  debt[:payment] = debt[:minimum]
end

if @pool > 0.0
# Allocate remainder to accounts in order of descending APR
  @config[:debts].each do |debt|
    break if @pool <= 0

    if (debt[:balance] - debt[:payment]) <= @pool
      @prompt.warn "LOG: available cash ($#{@pool}) is greater than the balance of #{debt[:creditor]} debt (less any planned minimum payments); recommend paying #{debt[:creditor]} the full balance of $#{debt[:balance].round(2)}." if ENV['DEBUG']
      @pool -= (debt[:balance] - debt[:payment])
      debt[:payment] = debt[:balance]
    else
      debt[:payment] += @pool
      @pool = 0.0
    end
  end
else
# Advise to make only minimum payments if there's not enough cash to do more
  @prompt.warn "Planned debt reduction costs are too high to go beyond minimum payments at this time; make those and move on."
end

#################
# List payments #
#################
@config[:debts].each do |debt|
  @prompt.ok "PAY #{debt[:creditor]}: #{debt[:payment].round(2)}"
  @total_debt -= debt[:payment]
  debt[:balance] -= debt[:payment]
end

@prompt.ok "Projected debt after today's payments: $#{@total_debt.to_i}"

##########################
# Write balances to file #
##########################
@prompt.ok "All done! Writing current state of finances to .cashier."
File.write('.cashier', Base64.encode64(JSON.dump(@config)))
