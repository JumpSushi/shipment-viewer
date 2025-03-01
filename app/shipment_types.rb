if ENV['LEMME_MITM']
  require 'openssl'
  OpenSSL::SSL::VERIFY_PEER = OpenSSL::SSL::VERIFY_NONE
  I_KNOW_THAT_OPENSSL_VERIFY_PEER_EQUALS_VERIFY_NONE_IS_WRONG = nil
end

require 'norairrecord'
require 'json'
require "active_support"
require 'active_support/core_ext/enumerable'

Norairrecord.api_key = ENV["AIRTABLE_PAT"]
Norairrecord.user_agent = "shipment viewer"
Norairrecord.base_url = ENV["AIRTABLE_BASE_URL"] if ENV["AIRTABLE_BASE_URL"]

def try_to_parse(str)
  begin
    return nil if str.nil?
    JSON.parse(str)
  rescue JSON::ParserError
    []
  end
end
class Shipment < Norairrecord::Table
  class << self
    def records(**args)
      raise "don't use Shipment directly!" unless self < Shipment
      return [] unless table_name
      super
    end

    def base_key
      ENV["AIRTABLE_BASE"];
    end

    attr_accessor :email_column

    def find_by_email(email)
      raise ArgumentError, "no email?" if email.nil? || email.empty?
      records :filter => "LOWER(TRIM({#{self.email_column}}))='#{email.downcase}'"
    end

    def check_for_any_by_email(email)
      raise ArgumentError, "no email?" if email.nil? || email.empty?
      records(:filter => "LOWER(TRIM({#{self.email_column}}))='#{email.downcase}'", fields: [], max_records: 1).any?
    end
  end

  def date
    raise NotImplementedError
  end

  def tracking_number
    nil
  end

  def tracking_link
    nil
  end

  def status_text
    "error fetching status! poke nora"
  end

  def source_url
    fields.dig("source_rec_url", "url")
  end

  def source_id
    source_url&.split('/').last
  end

  def icon
    "📦"
  end

  def hide_contents?
    false
  end

  def status_icon
    "?"
  end

  def shipped?
    nil
  end

  def description
    nil
  end

  def to_json(options = {})
    {
      id:,
      date:,
      tracking_link:,
      tracking_number:,
      type: self.class.name,
      type_text:,
      title: title_text,
      shipped: shipped?,
      icon:,
      description:,
      source_record: source_url
    }.compact.to_json
  end

  def internal_info_partial
    nil
  end
end

class WarehouseShipment < Shipment
  self.table_name = ENV["WAREHOUSE_TABLE"]
  self.email_column = "Email"

  def type_text
    "Warehouse shipment"
  end

  def title_text
    fields["user_facing_title"] || fields["Request Type"]&.join(', ') || "Who knows?"
  end

  def date
    self["Date Requested"]
  end

  def status_text
    case fields["state"]
    when "dispatched"
      "sent to warehouse..."
    when "mailed"
      "shipped!"
    when "ON_HOLD"
      "on hold... contact us for more info!"
    else
      "this shouldn't happen."
    end
  end

  def status_icon
    case fields["state"]
    when "dispatched"
      '<i class="fa-solid fa-dolly"></i>'
    when "mailed"
      '<i class="fa-solid fa-truck-fast"></i>'
    else
      '<i class="fa-solid fa-clock"></i>'
    end
  end

  def tracking_link
    fields["Warehouse–Tracking URL"]
  end

  def tracking_number
    fields["Warehouse–Tracking Number"] unless fields["Warehouse–Tracking Number"] == "Not Provided"
  end

  def hide_contents?
    fields["surprise"]
  end

  def icon
    return "🎁" if hide_contents? || title_text.start_with?("High Seas – Free")
    return "💵" if fields['Request Type']&.include?("Boba Drop grant")
    return "✉️" if fields["Warehouse–Service"]&.include?("First Class")
    "📦"
  end

  def shipped?
    fields["state"] == 'mailed'
  end

  def description
    return "it's a surprise!" if hide_contents?
    begin
      fields['user_facing_description'] ||
        fields["Warehouse–Items Shipped JSON"] && JSON.parse(fields["Warehouse–Items Shipped JSON"]).select { |item| (item["quantity"]&.to_i || 0) > 0 }.map do |item|
          "#{item["quantity"]}x #{item["name"]}"
        end
    rescue JSON::ParserError
      "error parsing JSON for #{source_id}!"
    end
  end

  def internal_info_partial
    :_warehouse_internal_info
  end
end

class HighSeasShipment < Shipment
  self.table_name = ENV["HSO_TABLE"]
  self.email_column = "recipient:email"

  def type_text
    "High Seas order"
  end

  def title_text
    "High Seas – #{fields["shop_item:name"] || "unknown?!"}"
  end

  def date
    self["created_at"]
  end

  has_subtypes "shop_item:fulfillment_type", {
    ["minuteman"] => "HSMinutemanShipment",
    ["hq_mail"] => "HSHQMailShipment",
    ["third_party_physical"] => "HS3rdPartyPhysicalShipment",
    ["agh"] => "HSRawPendingAGHShipment",
    ["agh_random_stickers"] => "HSRawPendingAGHShipment",
  }

  def status_text
    case fields["status"]
    when "PENDING_MANUAL_REVIEW", "on_hold"
      "awaiting manual review..."
    when "AWAITING_YSWS_VERIFICATION"
      "waiting for you to get verified..."
    when "pending_nightly"
      "we'll send it out when we can!"
    when "fulfilled"
      ["sent!", "mailed!", "on its way!"].sample
    else
      super
    end
  end

  def status_icon
    case fields["status"]
    when "PENDING_MANUAL_REVIEW", "on_hold"
      '<i class="fa-solid fa-hourglass-half"></i>'
    when "AWAITING_YSWS_VERIFICATION"
      '<i class="fa-solid fa-user-clock"></i>'
    when "pending_nightly"
      '<i class="fa-solid fa-clock"></i>'
    when "fulfilled"
      '<i class="fa-solid fa-truck-fast"></i>'
    end
  end

  def tracking_number
    fields["tracking_number"]
  end

  def tracking_link
    tracking_number && "https://parcelsapp.com/en/tracking/#{tracking_number}"
  end

  def icon
    return "🎁" if fields["shop_item:name"]&.start_with? "Free"
    super
  end

  def shipped?
    fields['status'] == 'fulfilled'
  end

  def internal_info_partial
    :_highseas_internal_info
  end
end

class HSMinutemanShipment < HighSeasShipment
  def status_text
    case fields["status"]
    when "pending_nightly"
      "will go out in next week's batch..."
    when "fulfilled"
      "has gone out/will go out over the next week!"
    else
      super
    end
  end

  def status_icon
    case fields["status"]
    when "pending_nightly"
      '<i class="fa-solid fa-envelopes-bulk"></i>'
    when "fulfilled"
      '<i class="fa-solid fa-envelope-circle-check"></i>'
    else
      super
    end
  end

  def icon
    "💌"
  end
end

class HSHQMailShipment < HighSeasShipment
  def type_text
    "High Seas shipment (from HQ)"
  end

  def status_text
    case fields["status"]
    when "pending_nightly"
      ["we'll ship it when we can!", "will be sent when dinobox gets around to it"].sample
    else
      super
    end
  end

  def status_icon
    case fields["status"]
    when "fulfilled"
      '<i class="fa-solid fa-truck"></i>'
    else
      super
    end
  end
end

class HS3rdPartyPhysicalShipment < HighSeasShipment
  def type_text
    "High Seas 3rd-party physical"
  end

  def status_text
    case fields["status"]
    when "pending_nightly"
      "will be ordered soon..."
    when "fulfilled"
      "ordered!"
    else
      super
    end
  end
end

class HSRawPendingAGHShipment < HighSeasShipment
  def type_text
    "Pending warehouse shipment"
  end

  def status_text
    case fields["status"]
    when "pending_nightly"
      "will be sent to the warehouse with the next batch!"
    else
      super
    end
  end

  def status_icon
    return '<i class="fa-solid fa-boxes-stacked"></i>' if fields['status'] == 'pending_nightly'
    super
  end
end

class BobaDropsShipment < Shipment
  self.table_name = ENV["BOBA_TABLE"]
  self.email_column = "Email"

  def title_text
    "Boba Drops!"
  end

  def type_text
    "Boba Drops Shipment"
  end

  def date
    self["[Shipment Viewer] Approved/pending at"] || 'error!'
  end

  def status_text
    case fields["Physical Status"]
    when "Pending"
      "pending!"
    when "Packed"
      "labelled!"
    when "Shipped"
      "shipped!"
    else
      "please contact leow@hackclub.com, something went wrong!"
    end
  end

  def status_icon
    case fields["Physical Status"]
    when "Pending"
      '<i class="fa-solid fa-clock"></i>'
    when "Packed"
      '<i class="fa-solid fa-dolly"></i>'
    when "Shipped"
      '<i class="fa-solid fa-truck-fast"></i>'
    else
      '<i class="fa-solid fa-circle-exclamation"></i>'
    end
  end

  def tracking_link
    fields["[INTL] Tracking Link"]
  end

  def tracking_number
    fields["[INTL] Tracking ID"]
  end

  def icon
    "🧋"
  end

  def shipped?
    fields["Physical Status"] == 'Shipped'
  end

  def description
    "shipment from boba drops <3"
  end
end

class SprigShipment < Shipment
  self.table_name = ENV["SPRIG_TABLE"]
  self.email_column = 'Email'

  def title_text
    "Sprig!"
  end

  def type_text
    "Sprig shipment"
  end

  def date
    fields["Created At"]
  end

  def status_text
    if shipped?
      "shipped via #{fields['Carrier'] || "...we don't know"}!"
    else
      "pending..."
    end
  end

  def status_icon
    if shipped?
      '<i class="fa-solid fa-truck"></i>'
    else
      '<i class="fa-solid fa-clock"></i>'
    end
  end

  def tracking_link
    fields['Tracking'] && "#{(fields['Tracking Base Link'] || 'https://parcelsapp.com/en/tracking/')}#{fields['Tracking']}"
  end

  def tracking_number
    fields["Tracking"]
  end

  def icon
    "🌱"
  end

  def shipped?
    fields['Sprig Status'] == 'Shipped'
  end

  def description
    "a #{fields['Color']&.downcase.concat ' '}Sprig!"
  end
end

class OneOffShipment < Shipment
  self.table_name = ENV["OO_TABLE"]
  self.email_column = 'email'

  SUPPORTED_FIELDS = %i[tracking_number status_text icon hide_contents? status_icon shipped? description type_text title_text]

  def tracking_link
    fields['tracking_link'] || (tracking_number && "https://parcelsapp.com/en/tracking/#{tracking_number}") || nil
  end

  def date
    fields['date'] || '2027-01-31'
  end

  def icon
    fields['icon'] || super
  end

  SUPPORTED_FIELDS.each do |field|
    define_method field do
      fields[field.to_s]
    end
  end
end

class PrintfulShipment < Shipment
  self.table_name = ENV["PF_TABLE"]
  self.email_column = '%order:recipient:email'

  has_subtypes "subtype", {
    "mystic_tavern" => "MysticTavernShipment"
  }
  def date
    fields['created'] || Date.parse(fields['%order:created']).iso8601
  end

  def title_text
    "something custom!"
  end

  def type_text
    "Printful shipment"
  end

  def icon
    "🧢"
  end

  def status_text
    case fields['status']
    when "pending"
      "pending..."
    when "onhold"
      "on hold!?"
    when "shipped"
      "shipped via #{fields['service']} on #{fields['ship_date']}!"
    when "started"
      "in production!"
    end
  end

  def shipped?
    fields['status'] == 'shipped'
  end

  def status_icon
    if shipped?
      '<i class="fa-solid fa-truck"></i>'
    else
      '<i class="fa-solid fa-clock"></i>'
    end
  end

  def description
    order_items = try_to_parse(fields['%order:items'])&.index_by { |item| item['id'] }
    shipment_items = try_to_parse(fields['items'])

    shipment_items.map do |si|
      name = order_items&.dig(si['item_id'], 'name') || '???'
      qty = si['quantity']
      qty != 1 ? "#{qty}x #{name}" : name
    end
  end

  def tracking_number
    fields['tracking_number']
  end

  def tracking_link
    fields['tracking_url'] if tracking_number
  end

  def internal_info_partial
    :_printful_internal_info
  end
end

class MysticTavernShipment < PrintfulShipment
  def title_text
    "Mystic Tavern shirts!"
  end

  def type_text
    "arrrrrrrrrrrrr"
  end

  def icon
    "👕"
  end

end

SHIPMENT_TYPES = [WarehouseShipment, HighSeasShipment, BobaDropsShipment, SprigShipment, OneOffShipment, PrintfulShipment].freeze
