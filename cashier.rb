require 'colorize'
require 'json'

# Mandatory expenses sometimes
RENT = 1900
WEWORK = 200

# Approx pool of cash week over week
PAYCHECK = 4400

# Don't plan for spending that leaves you with less than this amount
TARGET = 1100

debts = [
	{ creditor: "Chase",
	  apr: 0.25,
    balance: nil,
    minimum: nil,
	  payment: nil },
	{ creditor: "Klarna",
	  apr: 0.13,
    balance: nil,
    minimum: 169.04,
	  payment: nil },
	{ creditor: "SFFCU",
	  apr: 0.049,
    balance: nil,
    minimum: nil,
	  payment: nil },
	{ creditor: "Apple",
	  apr: 0.0,
    balance: nil,
    minimum: 306.79,
	  payment: nil },
]

total_debt = 0.0

begin
  file = File.read('.cashier')
  cashier_cache = JSON.parse(file)
  debts.each do |debt|
    cashier_cache.each do |c|
      if c['creditor'] == debt[:creditor]
        debt[:balance] = c['balance']
      else
        next
      end
    end
  end

  puts "Found the following balances in the .cashier file:".green
  debts.each { |d| puts "#{d[:creditor]}: #{d[:balance].round(2)}".bold }

  print "\nIs this correct? (Y/n): "
  correct_balances = gets.chomp
rescue Errno::ENOENT => e
  puts "No .cashier file found. Defaulting to manual input..."
  correct_balances = 'n'
end

unless correct_balances.downcase == 'y' or correct_balances.downcase == 'yes' or correct_balances.empty?
  debts.each do |debt|
    print "Enter #{debt[:creditor]} balance: $"
    debt[:balance] = gets.chomp.to_f
  end
end

debts.each do |debt|
  if debt[:balance].nil? or debt[:balance].zero?
    debts.delete debt
  else
    total_debt += debt[:balance]
  end
end

puts "Total Debt: #{total_debt}".red.bold

# Sort debts by APR
debts = debts.sort_by { |k| k[:apr] }
debts.reverse!

# Figure out if this paycheck has to cover rent as well as other 1st-of-the-month-type-things
today = Time.now
first_of_next_month = Time.new(today.year, (today.month + 1), 1)

pool = PAYCHECK - TARGET

if (first_of_next_month - today) <= 1209600
	puts "Your next paycheck needs rent money! Pay the rent. Removing rent money from available pool...".red
	pool -= RENT
	pool -= WEWORK
end

puts "AVAILABLE CASH: $#{pool}".green
puts "\n\n"

# Check minimum payments
debts.each do |debt|
  cmd = "Enter any minimum payment due to #{debt[:creditor]} & not yet paid this month"
  if debt[:minimum].nil?
    cmd = cmd + ": $"
  else
    cmd = cmd + " (#{debt[:minimum]}; RETURN to accept): $"
  end

  print cmd
  minimum = gets.chomp

  if minimum.nil? or minimum.empty? or minimum.to_f.zero?
    debt[:minimum] ||= 0.0
  else
    debt[:minimum] = minimum.to_f
    pool -= debt[:minimum]
  end

  debt[:payment] = debt[:minimum]
  print "\n"
end

if pool > 0.0
# Allocate remainder to accounts in order of descending APR
  debts.each do |debt|
    break if pool <= 0

    if (debt[:balance] - debt[:payment]) <= pool
      puts "LOG: available cash ($#{pool}) is greater than the balance of #{debt[:creditor]} debt (less any planned minimum payments); recommend paying #{debt[:creditor]} the full balance of $#{debt[:balance].round(2)}."
      pool -= (debt[:balance] - debt[:payment])
      puts "LOG: pool is now $#{pool}, after subtracting $#{debt[:balance].round(2)} (orig. balance) - $#{debt[:payment].round(2)} (any preexisting payment)"
      debt[:payment] = debt[:balance]
      puts "LOG: payment recommended for #{debt[:creditor]} is now $#{debt[:payment].round(2)}."
    else
      puts "LOG: available cash is not sufficient to cover the balance of #{debt[:creditor]} debt; recommend dumping the rest of your cash into lowering that balance."
      puts "LOG: adding remaining pool of cash ($#{pool.round(2)}) to any existing payment planned for #{debt[:creditor]} account; total recommended payment is $#{(debt[:payment] + pool).round(2)}"
      debt[:payment] += pool
      pool = 0.0
    end
  end
else
  puts "LOG: planned debt reduction costs are too high to go beyond minimum payments at this time; make those and move on. pool of available cash = $#{pool}; TARGET = #{TARGET}"
end

# List payments
debts.each do |debt|
  puts "PAY #{debt[:creditor]}: #{debt[:payment].round(2)}".blue.bold
  total_debt -= debt[:payment]
  debt[:balance] -= debt[:payment]
end

puts "Projected debt after today's payments: $#{total_debt.to_i}".green.bold

# Write balances to file
File.write('.cashier', JSON.dump(debts))