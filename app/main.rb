require 'sinatra/base'
require "sinatra/content_for"
require "sinatra/cookies"
require 'securerandom'
require 'active_support'
require 'active_support/core_ext/object/blank'

require_relative './helpers'
require_relative './awawawa'
require_relative './signage'

if ENV['SEND_REAL_EMAILS']
  require_relative './loops'
end

class ShipmentViewer < Sinatra::Base
  helpers Sinatra::ContentFor
  helpers Sinatra::Cookies
  helpers Sinatra::RenderMarkdownHelper
  helpers Sinatra::SchmoneyHelper
  helpers Sinatra::IIHelper

  set :host_authorization, permitted_hosts: []

  def footer_commit
    @footer_commit ||= if ENV['SOURCE_COMMIT']
                         "rev #{ENV['SOURCE_COMMIT'][...7]}"
                       else
                         "development!"
                       end
  end

  def gen_url(email)
    "#{ENV['BASE_URL']}/dyn/shipments/#{email}?signature=#{sign(email)}"
  end

  def mail_out_link(email)
    link = gen_url email
    if ENV['SEND_REAL_EMAILS']
      raise 'no transactional_id?' unless ENV['TRANSACTIONAL_ID']
      loops_send_transactional(email, ENV['TRANSACTIONAL_ID'], {link:})
    else
      puts "[EMAIL] to: #{email}, link: #{link}"
    end
  end

  def bounce_to_index!(message)
    @error = message
    halt erb :index
  end

  def external_link(text, href)
    "<a target='_blank' href='#{href}'>#{text} <i class='fa-solid fa-arrow-up-right-from-square'></i></a>"
  end
  set :sessions, true

  get '/' do
    erb :index
  end

  get '/internal' do
    @internal = true
    erb :index
  end

  get '/dyn/shipments/:email' do
    @show_ids = !!params[:ids]
    bounce_to_index! "invalid signature...? weird...." unless params[:signature] && sig_checks_out?(params[:email], params[:signature])
    @shipments = get_shipments_for_user params[:email]
    erb :shipments
  end

  get '/dyn/jason/:email' do
    content_type :json
    bounce_to_index! "just what are you trying to pull?" unless params[:signature] && sig_checks_out?(params[:email], params[:signature])

    @show_ids = !!params[:ids]

    @shipments = get_shipments_for_user params[:email]

    @shipments.to_json
  end

  post '/dyn/internal' do
    @internal = true

    unless cookies[:internal_key] && ENV["INTERNAL_KEYS"]&.split(',').include?(cookies[:internal_key])
      bounce_to_index! "not the right key ya goof"
    end

    @shipments = get_shipments_for_user params[:email]

    bounce_to_index! "couldn't find any shipments for #{params[:email]}" if @shipments.empty?

    @show_ids = true
    erb :shipments
  end

  post '/dyn/send_mail' do
    bounce_to_index! "couldn't find any shipments for that email! try another?" unless params[:email] && user_has_any_shipments?(params[:email])
    mail_out_link params[:email]
    erb :check_ur_email
  end

  get '/set_internal_key' do
    @internal = true
    erb :set_internal_key
  end

  post '/api/presign' do
    request.body.rewind
    key = request.env["HTTP_AUTHORIZATION"]
    unless key && ENV["PRESIGNING_KEYS"]&.split(',').include?(key)
      bounce_to_index! "not the right key ya goof"
    end
    email = request.body.read
    puts "#{key.split('@').last} is presigning a link for #{email}..."
    gen_url email
  end

  error 404 do
    erb :notfound
  end

  error do
    req_id = SecureRandom.urlsafe_base64(20)
    puts "LOGGING REQUEST ID: #{req_id}"
    bounce_to_index! "#{env['sinatra.error'].message} (request ID: #{req_id})"
  end

  get '/shipments' do
    email = params['email']
    signature = params['signature']

    if email && signature
      redirect to("/dyn/shipments/#{email}?signature=#{signature}"), 301
    else
      bounce_to_index! "lol wut"
    end
  end

end
