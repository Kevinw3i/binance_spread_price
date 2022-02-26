require 'rubygems'
require 'net/http'
require 'uri'
require 'json'
require 'colorize'
require 'faye/websocket'

URLS = {
  fs: 'wss://fstream.binance.com/ws/btcusdt@aggTrade',
  spot: 'wss://stream.binance.com:9443/ws/btcusdt@aggTrade'
}

MAX_SPREAD = 50
MIN_SPREAD = -50

up = '⬆'.colorize(:light_green)
down = '⬇'.colorize(:light_red)

module Tools; end

class Tools::Telegram
  DOMAIN = 'https://api.telegram.org/'
  TOKEN = ''
  METHOD = 'sendMessage'
  CHAT = ''
  class << self
    def send_message(message)
      uri = URI.parse("#{DOMAIN}bot#{TOKEN}/#{METHOD}?chat_id=#{CHAT}&text=#{message}")
      request = Net::HTTP::Get.new(uri)
      req_options = {
        use_ssl: uri.scheme == "https",
      }

      response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
        http.request(request)
      end
    end
  end
end

def setup_socket(urls)
  EM.run do
    urls.each do |key, url|
      ws = Faye::WebSocket::Client.new url, [], tls: { ping: 15 }

      ws.on :open do |event|
        variable_get(key)
      end

      ws.on :message do |msg|
        data = JSON.parse msg.data.to_s

        build_variable_set(key, data.dig('p').to_f)
        puts calculate_spread
      end

      ws.on :close do |event|
        p [:close, event.code, event.reason]
        ws = nil
      end
    end
  end
end

def build_variable_set(key, amount)
  instance_variable_set("@#{key}_price", amount)
end

def variable_get(key)
  instance_variables.include?("@#{key}_price".to_sym) ? instance_variable_get("@#{key}_price".to_sym) : build_variable_set(key, 0)
end

def calculate_spread
  spread_price = (@fs_price.to_f - @spot_price.to_f).round(2)

  if (spread_price > MAX_SPREAD || spread_price < MIN_SPREAD) && (@fs_price.to_f != 0.0 && @spot_price.to_f != 0.0)
    Thread.new { abnormal_spread(spread_price) }
  end

  "價差#{(spread_price)} / [現貨： #{@spot_price}, 期貨：#{@fs_price}]"
end

def abnormal_spread(spread_price)
  Tools::Telegram::send_message("BTC SPREAD #{spread_price} , SPOT #{@spot_price}, FUTURE #{@fs_price} AT #{Time.now}")
end

setup_socket(URLS)
