require 'rubygems'

require 'httparty'
require 'active_support'

class Arlo
  def initialize(email, password)
    @authed = false
    @email = email
    @password = password
    @headers = { 'DNT': '1',
                 'schemaVersion': '1',
                 'Host': 'arlo.netgear.com',
                 'Content-Type': 'application/json; charset=utf-8;',
                 'Referer': 'https://arlo.netgear.com/',
                 'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 11_1_2 like Mac OS X) AppleWebKit/604.3.5 (KHTML, like Gecko) Mobile/15B202 NETGEAR/v1 (iOS Vuezone)',}
  end

  def auth
    auth_params = { email: @email, password: @password }
    resp = HTTParty.post('https://arlo.netgear.com/hmsweb/login/v2',
                         body: auth_params.to_json,
                         headers: @headers)
    if resp.code == 200
      @headers['Authorization'] = resp.parsed_response['data']['token']
      @user_id = resp.parsed_response['data']['userId']
      true
      @authed = true
    else
      false
    end
  end

  def devices
    return false unless @authed
    @devices ||= HTTParty.get('https://arlo.netgear.com/hmsweb/users/devices', headers: @headers )['data']
  end

  def cameras
    return false unless @authed
    @cameras ||= devices.select { |d| d['deviceType'] == 'camera' }
  end

  def start_stream(camera)
    return false unless @authed

    body = gen_stream_body(camera, 'start')
    headers = @headers.dup
    headers['xcloudId'] = camera['xCloudId']
    r = HTTParty.post('https://arlo.netgear.com/hmsweb/users/devices/startStream', body: body, headers: headers)
    if r.code == 200
      r.parsed_response['data']['url'].gsub('rtsp://','rtsps://')
    else
      false
    end
  end

  def stop_stream(camera)
    return false unless @authed

    body = gen_stream_body(camera, 'stop')
    headers = @headers.dup
    headers['xcloudId'] = camera['xCloudId']
    r = HTTParty.post('https://arlo.netgear.com/hmsweb/users/devices/stopStream', body: body, headers: headers)
    r.code == 200
  end

  private

  def gen_stream_body(camera, action='start')
    { 'to': camera['parentId'],
      'from': "#{@user_id}_web",
      'resource': "cameras/#{camera['deviceId']}",
      'action': 'set',
      'responseUrl': '',
      'publishResponse': true,
      'transId': gen_transid,
      'properties': { 'activityState': "#{action}UserStream",
                      'cameraId': camera['deviceId'] }}.to_json
  end

  def float2hex(f) # this is some bullshit from the original python library
    w = f / 1
    d = f % 1

    # Do the whole:
    result = w.zero? ? 0 : ''
    while w != 0
      w, r = w.divmod(16)

      r = r.to_i
      if r > 9
        r = (r+55).chr
      else
        r = r.to_s
      end
      result = r + result
    end
    # And now the part:
    return result if d == 0
    result += '.'
    count = 0
    while d !=0
      d = d * 16
      w, d = d.divmod(1)
      w = w.to_i
      if w > 9
        w = (w+55).chr
      else
        w = w.to_s
      end
      result +=  w
      count += 1
      break if count > 15
    end
    result
  end

  def gen_transid
    hexfloat_string = float2hex(rand * (2 ** 32)).downcase
    time_string = (Time.now.to_i * 1e3 + (Time.now.to_f*1000)/1e3).to_s
    "web!" + hexfloat_string + "!" + time_string 
  end
end
