require 'colorize'

RENT = 1900
WEWORK = 200

PAYCHECK = 4400

TARGET = 1100

CHASE_CREDIT_APR = 0.25
KLARNA_CREDIT_APR = 0.12
SFFCU_CREDIT_APR = 0.049
APPLE_CREDIT_APR = 0.0

debts = [
	{ creditor: "Chase",
	  apr: 0.25,
	  payment: nil },
	{ creditor: "Klarna",
	  apr: 0.13,
	  payment: nil },
	{ creditor: "SFFCU",
	  apr: 0.049,
	  payment: nil },
	{ creditor: "Apple",
	  apr: 0.0,
	  payment: nil },
]

total_debt = 0.0

debts.each do |debt|
	print "Enter #{debt[:creditor]} balance: $"
	debt[:balance] = gets.chomp.to_f
	if debt[:balance].zero?
		debts.delete debt
	else
		total_debt += debt[:balance]
	end
end

puts "Total Debt: #{total_debt}".red.bold

debts = debts.sort_by { |k| k[:apr] }
debts.reverse!

today = Time.now
first_of_next_month = Time.new(today.year, (today.month + 1), 1)

pool = PAYCHECK

if (first_of_next_month - today) <= 1209600
	puts "Your next paycheck needs rent money! Pay the rent. Removing rent money from available pool...".red
	pool -= RENT
	pool -= WEWORK
end

puts "AVAILABLE CASH: $#{pool}".green
puts "\n\n"

while pool > TARGET
	# Check minimum payments
	debts.each do |debt|
		print "Enter the minimum payment due on the #{debt[:creditor]} account that you have not yet paid this month (RETURN if none): $"
		minimum = gets.chomp
		if minimum.nil? or minimum.empty? or minimum.to_f.zero?
			debt[:minimum] = 0.0
		else
			debt[:minimum] = minimum.to_f
			pool -= debt[:minimum]
		end
		debt[:payment] = debt[:minimum]
		print "\n"
	end

	# Allocate remainder to accounts in order of descending APR
	debts.each do |debt|
		if pool <= 0.0
			break
		end

		if debt[:balance] <= pool
			pool -= (debt[:balance] - debt[:payment])
			debt[:payment] = debt[:balance]
		else
			debt[:payment] += pool
			pool = 0.0
		end
	end

	# List payments
	debts.each do |debt|
		puts "PAY #{debt[:creditor]}: #{debt[:payment]}".blue.bold
		total_debt -= debt[:payment]
	end

	puts "Projected debt after today's payments: $#{total_debt.to_i}".green.bold
end