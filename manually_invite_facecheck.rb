client = Slack::Web::Client.new
client.users_list.members.each do |user_data|
  next if user_data.is_bot?
  data = {}
  data['user'] = user_data.id

  if user_data.profile.title == '' || user_data.profile.title.nil?
    if @r.get("profile_remind:#{data['user']}").nil?
      puts "no profile: #{data['user']} : #{user_data.name}"
      client.web_client.chat_postMessage(channel: data['user'],
                                         text: "Please update your user profile on slack so people know who you are!
                                         Edit it here: https://#{client.team.domain}.slack.com/team/#{user_data.name}",
                                         as_user: true)
      # slightly less than once a day
      @r.setex("profile_remind:#{data['user']}", 60 * 59 * 24, true)
    end
  else
    @r.hset('slack_title', data['user'], user_data.profile.title)
  end

  facecheck = @r.get("face:#{data['user']}")
  if facecheck.nil? && !ENV['GOOGLE_PROJECT_ID'].nil?
    puts "facecheck for #{user_data.name}"
    one_day = (60 * 60 * 24)
    @vision ||= Google::Cloud::Vision.new project: ENV['GOOGLE_PROJECT_ID']
    image = @vision.image user_data.profile.image_512
    if image.faces.size == 1
      # don't check for a month. we have max 1k per month free
      @r.setex("face:#{data['user']}", one_day * 30, true)

    else
      puts "no face!: #{data['user']}"
      # they changed it or wait one day check again. 1 day
      @r.setex("face:#{data['user']}", one_day, true)

      if @r.get("face_remind:#{data['user']}").nil?
        puts "reminding #{data['user']} : #{user_data.name} to add profile portrait"
        client.chat_postMessage(channel: data['user'],
                                           text: "Please update your Slack profile picture with a photo of your face so people can put a face to the name!
                                           Upload here: https://#{client.team.domain}.slack.com/team/#{user_data.name}",
                                           as_user: true)

        @r.setex("face_remind:#{data['user']}", one_day - 60, true)
      end
    end
  end
  #
  # if we haven't invited them AND they aren't registered...
  # invite them!
  if !@r.sismember('slinvited', data['user']) && @r.hget('slack_id2slack_name', data['user']).nil?
    puts "inviting #{user_data.name}"
    client.chat_postMessage(channel: data['user'],
                                       text: "Hi! Welcome! If you want to be on the Reception Kiosk (the computer up front), click on this link http://#{ENV['SERVER_HOST']}/slack_me_up/#{data['user']} when you are in the office, connected to the wifi. (It won't work anywhere else.) This will show your face when you are in the office. We do this so that people can put faces to names!",
                                       as_user: true)
    @r.sadd('slinvited', data['user'])
  end
end
