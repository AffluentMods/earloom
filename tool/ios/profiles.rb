# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Affluent Labs LLC
#
# Makes and installs the two App Store provisioning profiles (the app and its
# widget) through the App Store Connect API. Xcode's automatic provisioning
# needs an Apple ID signed in to Xcode on the build Mac; this needs only a
# team API key.
#
# Run it yourself on the Mac. It reads the API key file
# (~/.appstoreconnect/private_keys/AuthKey_<key id>.p8) to sign a token that
# lasts ten minutes, and never prints it:
#   SSL_CERT_FILE=/etc/ssl/cert.pem /opt/homebrew/opt/ruby/bin/ruby tool/ios/profiles.rb <key id> <issuer id>
# It needs Ruby 3 or newer. SSL_CERT_FILE is for a Homebrew Ruby, which does
# not find the system certificates by itself.
#
# Do this first on developer.apple.com: the App Group, both App IDs with App
# Groups linked to that group, and CarPlay Audio on the app's App ID. A profile
# made before that lacks them, and this script says so.
# Safe to run again: it replaces the two profiles it made before and touches
# no other profile.
#   ruby tool/ios/profiles.rb --self-test    checks the script's own parts without the key or the network
require 'openssl'
require 'json'
require 'base64'
require 'net/http'
require 'uri'

GROUP = 'group.com.affluentlabs.earloom'
CARPLAY = 'com.apple.developer.carplay-audio'
TARGETS = [
  { id: 'com.affluentlabs.earloom', profile: 'Earloom AppStore', carplay: true },
  { id: 'com.affluentlabs.earloom.NowPlayingWidget', profile: 'Earloom Widget AppStore', carplay: false },
].freeze
INSTALL_DIR = File.expand_path('~/Library/MobileDevice/Provisioning Profiles')

def b64(s) = Base64.urlsafe_encode64(s, padding: false)

# An ES256 token good for ten minutes.
def token(key_pem, key_id, issuer)
  key = OpenSSL::PKey::EC.new(key_pem)
  now = Time.now.to_i
  header = { alg: 'ES256', kid: key_id, typ: 'JWT' }
  claims = { iss: issuer, iat: now, exp: now + 600, aud: 'appstoreconnect-v1' }
  input = "#{b64(header.to_json)}.#{b64(claims.to_json)}"
  der = key.sign(OpenSSL::Digest.new('SHA256'), input)
  r, s = OpenSSL::ASN1.decode(der).value.map { |v| v.value.to_s(2).rjust(32, "\0")[-32, 32] }
  "#{input}.#{b64(r + s)}"
end

# What a profile grants, read from the property list inside its signed wrapper.
def granted(profile_bytes)
  xml = profile_bytes.dup.force_encoding('BINARY')[/<\?xml.*<\/plist>/m] || ''
  ent = xml[/<key>Entitlements<\/key>\s*<dict>(.*?)<\/dict>\s*<key>/m, 1] || xml
  {
    group: ent.include?(GROUP),
    carplay: !ent[/<key>#{Regexp.escape(CARPLAY)}<\/key>\s*<true\/>/].nil?,
  }
end

def self_test
  key = OpenSSL::PKey::EC.generate('prime256v1')
  t = token(key.to_pem, 'TESTKEY', 'test-issuer')
  parts = t.split('.')
  raise 'token does not have three parts' unless parts.size == 3
  raise 'signature is not 64 bytes' unless Base64.urlsafe_decode64(parts[2]).bytesize == 64
  sample = "junk<?xml version=\"1.0\"?><plist><dict><key>Entitlements</key><dict>" \
           "<key>#{CARPLAY}</key><true/><key>com.apple.security.application-groups</key>" \
           "<array><string>#{GROUP}</string></array></dict><key>Name</key><string>x</string></dict></plist>junk"
  g = granted(sample)
  raise 'did not read the sample profile' unless g[:group] && g[:carplay]
  none = granted('<?xml version="1.0"?><plist><dict><key>Entitlements</key><dict></dict><key>Name</key></dict></plist>')
  raise 'read entitlements that are not there' if none[:group] || none[:carplay]
  Dir[File.join(INSTALL_DIR, '*.mobileprovision')].first(1).each do |f|
    puts "   an installed profile reads as: #{granted(File.binread(f))}"
  end
  puts 'SELF-TEST OK'
end

if ARGV[0] == '--self-test'
  self_test
  exit
end

KEY_ID, ISSUER = ARGV
abort 'usage: profiles.rb <key id> <issuer id>   (the same two values you give altool)' unless KEY_ID && ISSUER
KEY_FILE = File.expand_path("~/.appstoreconnect/private_keys/AuthKey_#{KEY_ID}.p8")
abort "STOP: no key file for that key id in ~/.appstoreconnect/private_keys." unless File.exist?(KEY_FILE)
KEY_PEM = File.read(KEY_FILE)

def api(method, path, body = nil)
  uri = URI("https://api.appstoreconnect.apple.com#{path}")
  req = { 'GET' => Net::HTTP::Get, 'POST' => Net::HTTP::Post, 'DELETE' => Net::HTTP::Delete }.fetch(method).new(uri)
  req['Authorization'] = "Bearer #{token(KEY_PEM, KEY_ID, ISSUER)}"
  if body
    req['Content-Type'] = 'application/json'
    req.body = body.to_json
  end
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }
  json = res.body.to_s.empty? ? {} : JSON.parse(res.body)
  return json if res.code.to_i.between?(200, 299)
  detail = (json['errors'] || []).map { |e| e['detail'] || e['title'] }.compact.join(' / ')
  abort "STOP: Apple answered #{res.code} to #{method} #{path.split('?').first}: #{detail.empty? ? res.body.to_s[0, 300] : detail}"
end

def query(pairs) = pairs.map { |k, v| "#{URI.encode_www_form_component(k)}=#{URI.encode_www_form_component(v)}" }.join('&')

puts '== App IDs'
TARGETS.each do |t|
  found = api('GET', "/v1/bundleIds?#{query('filter[identifier]' => t[:id], 'limit' => '200')}")['data']
  match = found.find { |b| b.dig('attributes', 'identifier') == t[:id] }
  abort "STOP: the App ID #{t[:id]} is not registered yet. Register it on developer.apple.com (Identifiers), then run this again." unless match
  t[:bundle] = match['id']
  puts "   #{t[:id]}: registered"
end

puts '== distribution certificates'
now = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%S')
certs = api('GET', "/v1/certificates?#{query('filter[certificateType]' => 'DISTRIBUTION', 'limit' => '200')}")['data']
certs = certs.select { |c| c.dig('attributes', 'expirationDate').to_s > now }
abort 'STOP: the team has no valid Apple Distribution certificate.' if certs.empty?
puts "   #{certs.size} valid (the profiles accept each of them)"

Dir.mkdir(INSTALL_DIR) unless Dir.exist?(INSTALL_DIR)
problems = []
TARGETS.each do |t|
  puts "== profile \"#{t[:profile]}\""
  old = api('GET', "/v1/profiles?#{query('filter[name]' => t[:profile], 'limit' => '200')}")['data']
  old.select { |p| p.dig('attributes', 'name') == t[:profile] }.each do |p|
    api('DELETE', "/v1/profiles/#{p['id']}")
    stale = File.join(INSTALL_DIR, "#{p.dig('attributes', 'uuid')}.mobileprovision")
    File.delete(stale) if File.exist?(stale)
    puts '   replaced the one made before'
  end
  made = api('POST', '/v1/profiles', {
    data: {
      type: 'profiles',
      attributes: { name: t[:profile], profileType: 'IOS_APP_STORE' },
      relationships: {
        bundleId: { data: { type: 'bundleIds', id: t[:bundle] } },
        certificates: { data: certs.map { |c| { type: 'certificates', id: c['id'] } } },
      },
    },
  })['data']
  bytes = Base64.decode64(made.dig('attributes', 'profileContent'))
  path = File.join(INSTALL_DIR, "#{made.dig('attributes', 'uuid')}.mobileprovision")
  File.binwrite(path, bytes)
  g = granted(bytes)
  puts "   installed, valid until #{made.dig('attributes', 'expirationDate').to_s[0, 10]}"
  puts "   App Group: #{g[:group] ? 'yes' : 'MISSING'}#{t[:carplay] ? ", CarPlay Audio: #{g[:carplay] ? 'yes' : 'MISSING'}" : ''}"
  problems << "#{t[:id]}: turn on App Groups and pick #{GROUP}" unless g[:group]
  problems << "#{t[:id]}: turn on CarPlay Audio (it is under the capability requests Apple granted)" if t[:carplay] && !g[:carplay]
end

if problems.empty?
  puts 'DONE: both profiles are installed. Next: the build script.'
else
  puts 'NOT READY. On developer.apple.com, Identifiers, fix these and run this script again:'
  problems.each { |p| puts "   - #{p}" }
  exit 1
end
