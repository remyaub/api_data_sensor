# server.rb
require 'sinatra'
require "sinatra/namespace"
require 'mongoid'

# DB Setup
Mongoid.configure do |config|
  if ENV['MONGODB_URI']
    conn = Mongo::Connection.from_uri(ENV['MONGODB_URI'])
    uri = URI.parse(ENV['MONGODB_URI'])
    config.master = conn.db(uri.path.gsub(/^\//, ''))
  else
    Mongoid.load! "mongoid.config"
  end
end

# Models
class DataSet
  include Mongoid::Document

  field :device, type: String
  field :temperature, type: String
  field :humidity, type: String
  field :pressure, type: String
  field :timestamp, type: DateTime

  validates :device, presence: true

  index({ device: 'text' })

  scope :device, -> (device) { where(device: /^#{device}/) }
  scope :temperature, -> (temperature) { where(temperature: /^#{temperature}/) }
  scope :humidity, -> (humidity) { where(humidity: /^#{humidity}/) }
  scope :pressure, -> (pressure) { where(pressure: /^#{pressure}/) }
  scope :timestamp, -> (timestamp) { where(timestamp: /^#{timestamp}/) }
end

# Dataset ID to timestamp
def datasetid_to_timestamp(datasetid)
  timestamped = datasetid.id
  @timestamped = timestamp.id.generation_time.strftime('%d-%m-%Y %H:%M')
end

# Serializers
class DatasetSerializer

  def initialize dataset
    @dataset = dataset
  end

  def as_json(*)
    data = {
      id:@dataset.id.to_s,
      device:@dataset.device,
      temperature:@dataset.temperature,
      humidity:@dataset.humidity,
      pressure:@dataset.pressure,
      timestamp:@dataset.timestamp
    }
    data[:errors] = @dataset.errors if@dataset.errors.any?
    data
  end
end

# Endpoints
get '/' do
  'Database'
end

namespace '/api' do

  before do
    content_type 'application/json'
  end

  helpers do
    def base_url
      @base_url ||= "#{request.env['rack.url_scheme']}://#{request.env['HTTP_HOST']}"
    end

    def json_params
      begin
        JSON.parse(request.body.read)
      rescue
        halt 400, { message:'Invalid JSON' }.to_json
      end
    end

    def dataset
      @dataset ||= DataSet.where(id: params[:id]).first
    end

    def halt_if_not_found!
      halt(404, { message: 'Dataset Not Found'}.to_json) unless dataset
    end

    def serialize(dataset)
      DatasetSerializer.new(dataset).to_json
    end
  end

  get '/database' do
    dataset = DataSet.all
    [:device, :temperature, :humidity, :pressure, :timestamp].each do |filter|
      dataset = dataset.send(filter, params[filter]) if params[filter] 
    end
    dataset.map { |dataset| DatasetSerializer.new(dataset) }.to_json
  end

  get '/dataset/:id' do |id|
    halt_if_not_found!
    serialize(dataset)
  end

  post '/database' do
    dataset = DataSet.new(json_params)
    halt 422, serialize(dataset) unless dataset.save
    response.headers['Location'] = "#{base_url}/api/database/#{dataset.id}"
    status 201
  end

  patch 'dataset/:id' do |id|
    halt_if_not_found!
    halt 422, serialize(dataset) unless dataset.update_attributes(json_params)
    serialize(dataset)
  end

  delete '/dataset/:id' do |id|
    dataset.destroy if dataset
    status 204
  end
end