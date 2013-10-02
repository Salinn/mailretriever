require 'net/imap'     #Required to access the email accounts
require 'twilio-ruby'  #Required to send text messages
require 'yaml'         #Required to open up .yaml files

class Account
  attr_accessor :username, :password, :domain, :inbox, :email_distinction, :past_emails, :unread_total
end

@accounts   = YAML::load(File.open("accountNames.yaml"))  #Reads in account information
@other_info = YAML::load(File.open("environment.yaml")) #Reads in required environment variables

@account_sid        = @other_info["account_sid"]        #This is the account id for the twilio texting service
@auth_token         = @other_info["auth_token"]         #This is the generated password for the twilio account
@to_phone           = @other_info["to_phone"]           #This is the phone number that will recieve the message
@from_phone         = @other_info["from_phone"]         #This is the phone number that will send the message
@important_contacts = @other_info["important_contacts"] #This is the list of important contacts
@max_unread_emails  = @other_info["max_unread_emails"]  #This is the ceiling, once it is reached it will send a text

@from = Hash.new(0)

@client = Twilio::REST::Client.new @account_sid, @auth_token #This creates the login credentials for twilio

#This method connects to the email account and retrieves the number of new unread messages
#@param domain is the name of the server that needs to be connected to
#@oaram username is the username of the email account
#@param password is the password of the email account
#@param inbox is the location to check for unread emails
#@param email_distinction is the abbreviation at the start of each array that determines which email account it belongs to
#@param past_emails is the array<string> that contains all of the unread messages from the last time this was run
#@return count is an integer that represents the new unread messages
#@return temp_array is the array containing all of the unread messages
def get_unread_mail domain, username, password, inbox, past_emails
  count = 0
  temp_array = []
  imap = Net::IMAP.new(domain,993,true)
  imap.login(username,password)
  imap.select(inbox)
  imap.search(["NOT", "SEEN"]).each do |message_id|
    env = imap.fetch(message_id, "ENVELOPE")[0].attr["ENVELOPE"]
    @from["#{env.from[0].mailbox}@#{env.from[0].host}"] += 1
    unless past_emails.include? message_id
      count += 1
    end
    temp_array << message_id
  end
  imap.logout()
  imap.disconnect()
  return count, temp_array
end

#This method sends a text message with the number of unread emails
#@params = nil
#@return = confirmation text id
def send_text
  message = create_message
  @client.account.sms.messages.create(:body => message,:to => @to_phone,:from => @from_phone)
  @accounts.each { |x| x.unread_total = 0 if x.unread_total > @max_unread_emails }
end

#This method crafts the message
#@param = nil
#@return = A string with the message to send the end user
def create_message
  sum = 0
  @accounts.each { |x| sum += x.unread_total }
  message = "#{sum} new message!\n\n"

  @accounts.each { |x| message << "#{x.email_distinction} has #{x.unread_total} unread emails\n" }

  sum = 0
  @from.each { |k,v| sum += v if @important_contacts.include? k}
  message << "#{sum} important emails"
end

#This method determines if a text should be sent or not
#@params = nil
#@return = True if a message will be sent
#          False if a message will not be sent
def send_text?
  @from.each     { |k,v| return true if @important_contacts.include? k}
  @accounts.each { |x| return true if x.unread_total > @max_unread_emails }
  false
end

#This method contains the steps that need to be carried out to successfully check if I have unread emails
#It reads in the past emails, checks for new emails, sends a text message if it passes a condition, then updates the csv file
#@param = nil
#@return = nil
def main
  @accounts.each do |current_account|
    current_account.unread_total, current_account.past_emails = get_unread_mail current_account.domain,
                                                                               current_account.username,
                                                                               current_account.password,
                                                                               current_account.inbox,
                                                                               current_account.past_emails
  end

  send_text if send_text?
  File.write('accountNames.yaml', @accounts.to_yaml)
end

#This starts the program
main
