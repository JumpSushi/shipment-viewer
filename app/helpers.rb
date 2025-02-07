require 'active_support'
require 'active_support/number_helper'
require 'redcarpet'

module Sinatra
  module RenderMarkdownHelper
    class SVFlavoredMarkdown < Redcarpet::Render::HTML
      def pretty_shop_link(rec)
        "HS/LS order [#{rec}](https://airtable.com/appTeNFYcUiYfGcR6/tbl7Dj23N5tjLanM4/viwlw4aoTSsxC4KBA/#{rec})"
      end

      def link_qm_orders(text)
        return text unless text.start_with? 'QM:'
        text.gsub! /Shop order (rec\w+)/ do
          pretty_shop_link $1
        end
      end

      def link_shoporders(text)
        text.gsub! /<ShopOrder id='(\w+)'>/ do
          pretty_shop_link $1
        end
      end

      def link_arcade_orders(text)
        text.gsub! /\(arcade:orders:(rec\w+)\)/ do
          "Arcade order [#{$1}](https://airtable.com/app4kCWulfB02bV8Q/tblNUDETwMdUlBCSM/#{$1})"
        end
      end

      def preprocess(text)
        link_shoporders(text)
        link_qm_orders(text)
        link_arcade_orders(text)
        text
      end
    end
    def md(markdown)
      (@renderer ||= Redcarpet::Markdown.new(SVFlavoredMarkdown.new(link_attributes: {target: '_blank'}), autolink: true, tables: true)).render(markdown)
    end
  end
  module SchmoneyHelper
    def cashify(amount)
      ActiveSupport::NumberHelper.number_to_currency amount
    end
  end
  module IIHelper
    def render_ii(shipment, field, emoji, description, representation=nil, nilify=true)
      return unless shipment[field]
      return if nilify && shipment[field] == 0
      "<br/><abbr title='#{description}'>#{emoji}</abbr>: #{representation&.call(shipment) || shipment[field]}"
    end
  end
end