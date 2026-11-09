# Temporary App Store signing for CI.
#   ruby scripts/asc_signing.rb setup    -> creates a distribution certificate + App Store profiles
#   ruby scripts/asc_signing.rb cleanup  -> deletes what setup created (run even if the build failed)
# Needs env: KID, ISS, KEY_PATH (App Store Connect API key), WORK (folder for files).
require "openssl"
require "base64"
require "json"
require "time"
require "net/http"
require "fileutils"

WORK = ENV.fetch("WORK")
STATE = File.join(WORK, "signing.json")
BUNDLES = { "app" => "com.daad.keyboard", "ext" => "com.daad.keyboard.ext" }

def token
  b64 = ->(s) { Base64.urlsafe_encode64(s, padding: false) }
  key = OpenSSL::PKey::EC.new(File.read(ENV.fetch("KEY_PATH")))
  now = Time.now.to_i
  input = b64.(JSON.generate(alg: "ES256", kid: ENV.fetch("KID").strip, typ: "JWT")) + "." +
          b64.(JSON.generate(iss: ENV.fetch("ISS").strip, iat: now, exp: now + 900, aud: "appstoreconnect-v1"))
  der = OpenSSL::ASN1.decode(key.sign(OpenSSL::Digest::SHA256.new, input))
  input + "." + b64.(der.value.map { |v| v.value.to_s(2).rjust(32, "\0") }.join)
end

def api(method, path, body = nil)
  uri = URI("https://api.appstoreconnect.apple.com" + path)
  req = { "GET" => Net::HTTP::Get, "POST" => Net::HTTP::Post, "DELETE" => Net::HTTP::Delete }[method].new(uri)
  req["Authorization"] = "Bearer #{token}"
  req["Content-Type"] = "application/json"
  req.body = JSON.generate(body) if body
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }
  data = res.body.to_s.empty? ? {} : JSON.parse(res.body)
  unless res.code.start_with?("2")
    detail = (data["errors"] || []).map { |e| "#{e["title"]}: #{e["detail"]}" }.join(" | ")
    raise "App Store Connect #{method} #{path} failed (#{res.code}): #{detail}"
  end
  data
end

def setup
  FileUtils.mkdir_p(WORK)
  state = { "profiles" => {} }
  key = OpenSSL::PKey::RSA.new(2048)
  File.write(File.join(WORK, "dist.key"), key.to_pem)
  csr = OpenSSL::X509::Request.new
  csr.version = 0
  csr.subject = OpenSSL::X509::Name.parse("/CN=Daad CI/O=Daad")
  csr.public_key = key.public_key
  csr.sign(key, OpenSSL::Digest::SHA256.new)

  cert = api("POST", "/v1/certificates", { data: { type: "certificates",
    attributes: { certificateType: "DISTRIBUTION", csrContent: csr.to_pem } } })["data"]
  state["certificate"] = cert["id"]
  File.write(STATE, JSON.generate(state))
  der = Base64.decode64(cert["attributes"]["certificateContent"])
  File.write(File.join(WORK, "dist.pem"), OpenSSL::X509::Certificate.new(der).to_pem)
  puts "Created temporary distribution certificate #{cert["id"]}"

  BUNDLES.each do |role, identifier|
    bundle = api("GET", "/v1/bundleIds?filter[identifier]=#{identifier}&filter[platform]=IOS")["data"]
             .find { |b| b["attributes"]["identifier"] == identifier }
    raise "Bundle ID #{identifier} not found in the developer account" unless bundle
    name = "Daad CI #{role} #{ENV["GITHUB_RUN_ID"] || Time.now.to_i}"
    profile = api("POST", "/v1/profiles", { data: { type: "profiles",
      attributes: { name: name, profileType: "IOS_APP_STORE" },
      relationships: {
        bundleId: { data: { type: "bundleIds", id: bundle["id"] } },
        certificates: { data: [{ type: "certificates", id: cert["id"] }] } } } })["data"]
    state["profiles"][role] = { "id" => profile["id"], "name" => name, "bundle" => identifier }
    File.write(STATE, JSON.generate(state))
    dir = File.expand_path("~/Library/MobileDevice/Provisioning Profiles")
    FileUtils.mkdir_p(dir)
    File.binwrite(File.join(dir, "#{profile["attributes"]["uuid"]}.mobileprovision"),
                  Base64.decode64(profile["attributes"]["profileContent"]))
    puts "Created profile #{name}"
  end

  # Values the next workflow steps read.
  File.open(ENV.fetch("GITHUB_ENV"), "a") do |f|
    f.puts "APP_PROFILE=#{state["profiles"]["app"]["name"]}"
    f.puts "EXT_PROFILE=#{state["profiles"]["ext"]["name"]}"
  end
end

# Apple checks the signing certificate while it processes an upload, which can take a while after the
# upload finishes. Revoking it too early fails the build with "90721 Certificate Revoked", so when
# WAIT_FOR_BUILD is set, wait until the newest build of the app is no longer processing.
def wait_for_processing
  started = Time.now
  app = api("GET", "/v1/apps?filter[bundleId]=com.daad.keyboard")["data"].first
  return puts("App not found, not waiting") unless app
  sleep 60
  loop do
    build = api("GET", "/v1/builds?filter[app]=#{app["id"]}&sort=-uploadedDate&limit=1")["data"].first
    st = build && build["attributes"]["processingState"]
    fresh = build && Time.parse(build["attributes"]["uploadedDate"]) > started - 20 * 60
    puts "Newest build #{build && build["attributes"]["version"]}: #{st}#{fresh ? "" : " (older upload, waiting for the new one)"}"
    break if fresh && st != "PROCESSING"
    break puts("Stopped waiting after 45 minutes") if Time.now - started > 45 * 60
    sleep 60
  end
rescue => e
  puts "Could not check processing (#{e}); waiting 20 minutes instead"
  sleep 20 * 60
end

def cleanup
  return puts("Nothing to clean up") unless File.exist?(STATE)
  state = JSON.parse(File.read(STATE))
  wait_for_processing if ENV["WAIT_FOR_BUILD"] == "1"
  (state["profiles"] || {}).each_value do |p|
    api("DELETE", "/v1/profiles/#{p["id"]}") rescue puts("Could not delete profile #{p["name"]}: #{$!}")
  end
  if state["certificate"]
    api("DELETE", "/v1/certificates/#{state["certificate"]}") rescue puts("Could not delete certificate: #{$!}")
    puts "Deleted temporary certificate #{state["certificate"]}"
  end
end

case ARGV[0]
when "setup" then setup
when "cleanup" then cleanup
else abort "usage: asc_signing.rb setup|cleanup"
end
