require 'benevolent_gaze/version'

module BenevolentGaze
  # Your code goes here...
end

Airbrake.configure do |config|
  config.host = ENV['AIRBRAKE_HOST']
  config.project_id = 5 # required, but any positive integer works
  config.project_key = ENV['AIRBRAKE_KEY']
end
