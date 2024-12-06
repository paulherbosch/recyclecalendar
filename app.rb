require 'sinatra'
require 'sinatra/multi_route'
require 'sinatra/logger'
require 'json'
require 'dotenv/load'
require 'curb'
require 'icalendar'
require 'date'
require 'active_support'
require 'active_support/core_ext' 
require 'mysql2'
require 'sequel'
require 'net/ping'
require 'base64'

include ERB::Util

##############################
# Initialize
# Read app config files etc

# begin sinatra configure block
configure do
  # enable sessions
  use Rack::Session::Pool

  # enable logging
  set :root, Dir.pwd
  set :logger, Logger.new(STDOUT)

  # bind
  set :bind, '0.0.0.0'

  # populate appconfig hash via environment vars or read from the .env config file
  $appconfig = Hash.new

  # Mysql backend
  #
  $appconfig['mysql_host']     = ENV['MYSQL_HOST']     || nil
  $appconfig['mysql_database'] = ENV['MYSQL_DATABASE'] || nil
  $appconfig['mysql_user']     = ENV['MYSQL_USER']     || nil
  $appconfig['mysql_password'] = ENV['MYSQL_PASSWORD'] || nil

  #
  # Global Variables
  #

  # Recycle App
  $appconfig['recycleapp_api_url']   = ENV['RECYCLEAPP_API_URL']   || nil
 
  # Timezone
  $appconfig['timezone'] = ENV['TIMEZONE']  || nil

  # proxy
  $appconfig['proxies']      = ENV['PROXIES'] || nil
  $appconfig['proxytesturl'] = ENV['PROXYTESTURL'] || nil

  # Pickup Events Cache TTL
  $appconfig['cache_ttl_days'] = ENV['CACHE_TTL_DAYS'] || nil


  # Exclude list
  $appconfig['excludes'] = ENV['EXCLUDES'] || nil
end

############################
# Start Function Definitions
#

helpers do
  # this is the main function
  # it pulls a pickup calendar from www.recycleapp.be based on postalcode, streetname and housenumber
  #
  def get_pickup_dates(postalcode,streetname,housenumber)
    # do we need to use a proxy?
    if $appconfig['proxies']
      $proxyserver = select_proxy($appconfig['proxies'])

      if $proxyserver == "no proxy selected"
        @error_content = "Unable to reach one of the configured proxy servers."
        halt erb :ics
      end
    end

    zipcodeid        = fetch_zipcodeid(postalcode)
    streetid         = fetch_streetid(streetname,zipcodeid)

    pickup_date_params = Hash.new
    pickup_date_params['zipcodeId']   = zipcodeid
    pickup_date_params['streetId']    = streetid['street']
    pickup_date_params['houseNumber'] = housenumber
    pickup_date_params['fromDate']    = $from_until_date['from']
    pickup_date_params['untilDate']   = $from_until_date['until']

    # fetch the actual pickup events
    pickup_dates = Curl.get("#{$appconfig['recycleapp_api_url']}/collections", pickup_date_params) do |curl|
      curl.headers["Accept"]          = "application/json, text/plain, */*"
      curl.headers["x-consumer"]      = "recycleapp.be"
      if $appconfig['proxies']
        curl.proxy_url                  = $proxyserver
      end
    end

    # convert the received events into a Ruby data structure
    pickup_events_json = JSON.parse(pickup_dates.body_str)

    # fetch timestamps,fractions and color from pickup_events_json as that is all we need
    pickup_events_simple = Array.new
    pickup_events_json['items'].each do |item|
      if item['type'] == "collection"
        pickup = Hash.new
        pickup['timestamp']          = item['timestamp']
        pickup['formattedtimestamp'] = Date.parse(item['timestamp']).strftime("%A %d-%m-%Y")
        pickup['fraction']           = item['fraction']['name']['nl'] 
        pickup['color']              = item['fraction']['color']
        pickup_events_simple.push(pickup)
      end
    end

    return pickup_events_simple
  end

  def set_from_until_date(thismonth)
    # Untildate is last day of this year. Last date with events in calendar
    # Unless month is december, then search for events next year
    # thismonth = Date.today.strftime("%m")
    if thismonth == "12"
      untilDate = Date.today.next_month.end_of_year.strftime("%F")
    else
      untilDate = Date.today.end_of_year.strftime("%F")
    end

    dates = Hash.new
    dates['from']  = Date.today.beginning_of_month.strftime("%F")
    dates['until'] = untilDate

    return dates
  end

  def fetch_zipcodeid(postalcode)
    postalcode_resp = Curl.get("#{$appconfig['recycleapp_api_url']}/zipcodes?q=#{postalcode}") do |curl|
      curl.headers["Accept"]          = "application/json, text/plain, */*"
      curl.headers["x-consumer"]      = "recycleapp.be"
      if $appconfig['proxies']
        curl.proxy_url                  = $proxyserver
      end
    end

    postalcode_id = String.new
    postalcode_json = JSON.parse(postalcode_resp.body_str)
    postalcode_json['items'].each do |item|
      if item['code'] == "#{postalcode}"
        postalcode_id = item['id']
        break
      end
    end

    return postalcode_id
  end

  def fetch_streetid(streetname,zipcodeid)
    streetname_resp = Curl.get("#{$appconfig['recycleapp_api_url']}/streets?q=#{streetname}&zipcodes=#{zipcodeid}") do |curl|
      curl.headers["Accept"]          = "application/json, text/plain, */*"
      curl.headers["x-consumer"]      = "recycleapp.be"
      if $appconfig['proxies']
        curl.proxy_url                  = $proxyserver
      end
    end

    street_id    = String.new
    gemeentenaam = String.new
    city         = String.new

    streetname_json = JSON.parse(streetname_resp.body_str)
    streetname_json['items'].each do |item|
      if item['names'].has_value? "#{streetname}"
        street_id = item['id']
        city      = item['zipcode'][0]['names'][0]['nl']
        break
      end
    end

    street_city = Hash.new
    street_city['street'] = street_id
    street_city['city']   = city

    # return street_id
    return street_city
  end

  # store pickup events in mysql cache
  #
  def add_pickup_events_to_database(ics_formatted_url,pickup_events,fromdate,untildate)
    # connect to the database
    $DB = Sequel.connect(
      adapter:  'mysql2',
      test:     true,
      user:     $appconfig['mysql_user'],
      password: $appconfig['mysql_password'],
      host:     $appconfig['mysql_host'],
      port:     $appconfig['mysql_port'],
      database: $appconfig['mysql_database'])

    pickup_event_cache = $DB[:cache]

    # delete expired cache entry
    logger.info("=== INFO - removing expired cache record from database for #{ics_formatted_url} ===")
    pickup_event_cache.where(request_url: ics_formatted_url).delete

    # add cache entry to database
    logger.info("=== INFO - add new cache record to database for #{ics_formatted_url} ===")
    pickup_event_cache.insert(
      request_url:   ics_formatted_url,
      fromdate:      fromdate,
      untildate:     untildate,
      pickup_events: pickup_events)

    # clean up the database connection
    $DB.disconnect
  end

  # retrieve list of pickups for a cached address
  #
  def retrieve_cache_from_database(ics_formatted_url)
    # connect to the database
    $DB = Sequel.connect(
      adapter:  'mysql2',
      test:     true,
      user:     $appconfig['mysql_user'],
      password: $appconfig['mysql_password'],
      host:     $appconfig['mysql_host'],
      port:     $appconfig['mysql_port'],
      database: $appconfig['mysql_database'])

    # create addresses table if it doesn't exist
    unless $DB.table_exists?(:cache)
      $DB.create_table :cache do
        primary_key :id
        column :created, 'timestamp', :default => Sequel.lit("now()")
        column :request_url, String
        column :fromdate, String
        column :untildate, String
        column :pickup_events, 'mediumtext'
      end
    end

    # search for ics calendar
    cached_pickup_events = $DB[:cache].where(:request_url => ics_formatted_url)

    # clean up the database connection
    $DB.disconnect

    return cached_pickup_events
  end

  # create an ICS object based on the events we pulled from www.recycleapp.be
  #
  def generate_ics(events,timezone, excludes)
    # create calendar object
    cal = Icalendar::Calendar.new

    # set calendar timezone
    cal.timezone do |t|
      t.tzid = timezone
    end

    if excludes
      excludelist = excludes.split(',')
    end

    # populate calendar with events
    events.each do |pickup_event|
      # skip to the next pickup_event if we're not interested in this fraction.
      if excludes
        next if excludelist.include? pickup_event['fraction']
      end

      dt = Date.parse(pickup_event['timestamp'])
      event = Icalendar::Event.new
      event.dtstart = Icalendar::Values::Date.new(dt)
      event.dtend   = Icalendar::Values::Date.new(dt + 1)
      event.summary = pickup_event['fraction']
      event.transp = 'TRANSPARENT'

      # add the new event to the calendar object
      cal.add_event(event)
    end 

    ical_string = cal.to_ical

    return ical_string
  end

  # loop over a list of proxies and select one that can reach www.recycleapp.be
  #
  def select_proxy(proxies)
    # convert comma separtated list of proxies into array
    proxylist   = proxies.split(",")

    # loop over proxylist and select a proxy that can reach www.recycleapp.be
    proxylist.each do |proxy|
      logger.info("=== INFO - testing proxy server:     #{proxy} ===")
      checked_proxy = proxy_check(proxy)

      if checked_proxy['response_code'] == 200
        logger.info("=== INFO - selected proxy server:    #{proxy} ===")
        return proxy
        break
      else
        logger.info("=== INFO - proxy did not return 200: #{proxy} ===")
      end
    end

    return "no proxy selected"
  end

  # check if a proxy is reachable and if it can reach www.recycleapp.be
  #
  def proxy_check(proxy)
    proxytotest                     = Hash.new
    proxytotest['address_and_port'] = proxy
    proxytotest['address']          = proxy[/(.*?):(\d+)/,1]
    proxytotest['port']             = proxy[/(.*?):(\d+)/,2]

    # if the proxy can be reached on it's ip address and tcp port, test if it can reach the testurl
    proxy = Net::Ping::TCP.new(proxytotest['address'], proxytotest['port'].to_i)
    if proxy.ping?
      @resp = Curl::Easy.new($appconfig['proxytesturl']) { |easy|
        easy.proxy_url  = proxytotest['address']
        easy.proxy_port = proxytotest['port'].to_i
        easy.follow_location = true
        easy.proxy_tunnel = true
      }

      begin
        @resp.perform
        @resp.response_code
        proxytotest['response_code'] = @resp.response_code
      rescue
        logger.info("=== ERROR: could not connect to #{proxy} ===")
        proxytotest['response_code'] = '404'
      end
    else
      logger.info("=== ERROR - proxy ping failed: #{proxy} ===")
      proxytotest['response_code'] = '404'
    end

    return proxytotest
  end
end

#
# End function definitions
##########################

#######################
# Start URI Definitions
#

# info
route :get, '/info' do
  erb :info
end

# main page
route :get, :post, '/' do
  postalcode    = params['postalcode']  || $appconfig['postalcode']
  streetname    = params['streetname']  || $appconfig['streetname']
  housenumber   = params['housenumber'] || $appconfig['housenumber']
  timezone      = params['timezone']    || $appconfig['timezone']
  excludes      = params['excludes']    || $appconfig['excludes']

  $from_until_date = set_from_until_date(Date.today.strftime("%m"))

  # set ics formatted url, used in the :ics template
  @ics_formatted_url = "#{request.scheme}://#{request.host}/?postalcode=#{postalcode}&streetname=#{streetname}&housenumber=#{housenumber}&format=ics"

  # check if a valid request comes in
  if params['getpickups'] or params['format'] == 'ics' or (postalcode and streetname and housenumber)
    # check if pickup events already exists in the mysql cache
    cached_pickup_events = retrieve_cache_from_database(@ics_formatted_url)

    # if the address was found and the entry is younger than $appconfig['cache_ttl_days']
    # do not contact www.recycleapp.be but display cached info instead
    if cached_pickup_events.count > 0 and cached_pickup_events.map(:created)[0] > $appconfig['cache_ttl_days'].to_i.days.ago
      cache_create_date = cached_pickup_events.map(:created)[0]
      logger.info("=== INFO - retrieving cached entry created on #{cache_create_date} ===")

      @pickup_events = JSON.parse(Base64.decode64(cached_pickup_events.map(:pickup_events)[0]))
      @fromdate      = cached_pickup_events.map(:fromdate)[0]
      @untildate     = cached_pickup_events.map(:untildate)[0]
    else
      # get list of pickups from www.recycleapp.be
      logger.info("=== INFO - no cache hit, retrieving from www.recycleapp.be ===")
      @pickup_events = get_pickup_dates(postalcode,streetname.split.map(&:capitalize).join(' '),housenumber)

      # store freshly retrieved pickup events in the database cache
      add_pickup_events_to_database(@ics_formatted_url,Base64.encode64(@pickup_events.to_json),$from_until_date['from'],$from_until_date['until'])
    end

    # generate a hash with info to display in the :ics template
    @pickupinfo = Hash.new
    @pickupinfo['postalcode']   = postalcode 
    @pickupinfo['streetname']   = streetname 
    @pickupinfo['housenumber']  = housenumber 
    @pickupinfo['fromdate']     = @fromdate
    @pickupinfo['untildate']    = @untildate

    if params['format'] == 'ics'
      # render ICS format and halt
      halt generate_ics(@pickup_events,timezone,excludes)
    else
      # or render html and halt
      halt erb :ics
    end
  end

  # if no valid request came in, display default homepage
  erb :ics
end
