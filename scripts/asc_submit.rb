# Sends an App Store version for review: sets What's New, picks the build, submits.
#   VERSION=1.1.2 BUILD=62 DRY_RUN=1 ruby scripts/asc_submit.rb   -> only shows what it would do
# Needs env: KID, ISS, KEY_PATH (App Store Connect API key).
require "openssl"
require "base64"
require "json"
require "net/http"

VERSION = ENV.fetch("VERSION")
BUILD = ENV.fetch("BUILD")
DRY = ENV["DRY_RUN"] == "1"

WHATS_NEW = {
  "ar" => <<~TEXT.strip,
    - الكيبورد بقى أخف وأسرع، والذاكرة أقل.
    - التصحيح التلقائي مبقاش يغيّر الكلام المصري.
    - في (ع+En): الاتجاه بيقلب لوحده مع لغة الكتابة، وفيه زرار ⇄ لو عايز تقلبه بإيدك.
    - في (ع+En): صفحة الأرقام بقت إنجليزي وانت بتكتب إنجليزي.
    - في (ع+En): الحروف العربي الزيادة بقت أصغر في الشكل الإنجليزي، والحروف الإنجليزي أكبر.
    - الكتابة السريعة بقت أدق، والمسح المطوّل بيكمّل للآخر.
    - تحديد الكلام وSelect All مبقوش بيتقلوا الكيبورد.
    - إصلاحات وتحسينات تانية.
  TEXT
  "en" => <<~TEXT.strip,
    - Lighter, faster keyboard that uses less memory.
    - Autocorrect no longer changes Egyptian Arabic words.
    - English + العربية: the writing side follows the language you type, plus a new ⇄ key to flip it by hand.
    - English + العربية: the numbers page switches to English while you type English.
    - English + العربية: the extra Arabic keys are smaller in the English look, giving the English letters more room.
    - More accurate fast typing; holding delete keeps going to the end.
    - Selecting text and Select All no longer slow the keyboard down.
    - Other fixes and improvements.
  TEXT
}

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
  klass = { "GET" => Net::HTTP::Get, "POST" => Net::HTTP::Post, "PATCH" => Net::HTTP::Patch }[method]
  req = klass.new(uri)
  req["Authorization"] = "Bearer #{token}"
  req["Content-Type"] = "application/json"
  req.body = JSON.generate(body) if body
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }
  data = res.body.to_s.empty? ? {} : JSON.parse(res.body)
  unless res.code.start_with?("2")
    detail = (data["errors"] || []).map { |e| "#{e["title"]}: #{e["detail"]}" }.join(" | ")
    raise "#{method} #{path} failed (#{res.code}): #{detail}"
  end
  data
end

def change(desc)
  if DRY
    puts "[dry run] would #{desc}"
    nil
  else
    puts "→ #{desc}"
    yield
  end
end

app = api("GET", "/v1/apps?filter[bundleId]=com.daad.keyboard")["data"].first or abort("App not found")
app_id = app["id"]

versions = api("GET", "/v1/apps/#{app_id}/appStoreVersions?filter[platform]=IOS&limit=5")["data"]
versions.each { |v| puts "version #{v["attributes"]["versionString"]}: #{v["attributes"]["appStoreState"]}" }
version = versions.find { |v| v["attributes"]["versionString"] == VERSION }
if version.nil?
  version = change("create version #{VERSION}") do
    api("POST", "/v1/appStoreVersions", { data: { type: "appStoreVersions",
      attributes: { platform: "IOS", versionString: VERSION },
      relationships: { app: { data: { type: "apps", id: app_id } } } } })["data"]
  end
  exit 0 if version.nil?
end
state = version["attributes"]["appStoreState"]
editable = %w[PREPARE_FOR_SUBMISSION DEVELOPER_REJECTED REJECTED METADATA_REJECTED INVALID_BINARY]
abort "Version #{VERSION} is #{state}: not editable, nothing sent" unless editable.include?(state)

locs = api("GET", "/v1/appStoreVersions/#{version["id"]}/appStoreVersionLocalizations")["data"]
locs.each do |l|
  locale = l["attributes"]["locale"]
  text = locale.start_with?("ar") ? WHATS_NEW["ar"] : WHATS_NEW["en"]
  change("set What's New for #{locale}") do
    api("PATCH", "/v1/appStoreVersionLocalizations/#{l["id"]}",
        { data: { type: "appStoreVersionLocalizations", id: l["id"], attributes: { whatsNew: text } } })
  end
end

build = api("GET", "/v1/builds?filter[app]=#{app_id}&filter[version]=#{BUILD}&filter[preReleaseVersion.version]=#{VERSION}")["data"].first
abort "Build #{BUILD} of #{VERSION} not found" unless build
b = build["attributes"]
puts "build #{BUILD}: #{b["processingState"]}, expired=#{b["expired"]}, usesNonExemptEncryption=#{b["usesNonExemptEncryption"].inspect}"
abort "Build #{BUILD} is not ready" unless b["processingState"] == "VALID" && !b["expired"]
if b["usesNonExemptEncryption"].nil?
  change("mark build #{BUILD} as using no non-exempt encryption") do
    api("PATCH", "/v1/builds/#{build["id"]}", { data: { type: "builds", id: build["id"], attributes: { usesNonExemptEncryption: false } } })
  end
end
change("attach build #{BUILD} to #{VERSION}") do
  api("PATCH", "/v1/appStoreVersions/#{version["id"]}/relationships/build", { data: { type: "builds", id: build["id"] } })
end

open_subs = api("GET", "/v1/reviewSubmissions?filter[app]=#{app_id}&filter[platform]=IOS&filter[state]=READY_FOR_REVIEW,WAITING_FOR_REVIEW,IN_REVIEW,UNRESOLVED_ISSUES")["data"]
open_subs.each { |s| puts "review submission #{s["id"]}: #{s["attributes"]["state"]}" }
abort "A review is already waiting or in progress: nothing sent" if open_subs.any? { |s| %w[WAITING_FOR_REVIEW IN_REVIEW].include?(s["attributes"]["state"]) }
sub = open_subs.find { |s| s["attributes"]["state"] == "READY_FOR_REVIEW" }
sub ||= change("create a review submission") do
  api("POST", "/v1/reviewSubmissions", { data: { type: "reviewSubmissions", attributes: { platform: "IOS" },
    relationships: { app: { data: { type: "apps", id: app_id } } } } })["data"]
end
exit 0 if sub.nil?
items = api("GET", "/v1/reviewSubmissions/#{sub["id"]}/items")["data"]
if items.empty?
  change("add version #{VERSION} to the review submission") do
    api("POST", "/v1/reviewSubmissionItems", { data: { type: "reviewSubmissionItems",
      relationships: { reviewSubmission: { data: { type: "reviewSubmissions", id: sub["id"] } },
                       appStoreVersion: { data: { type: "appStoreVersions", id: version["id"] } } } } })
  end
end
change("submit for review") do
  api("PATCH", "/v1/reviewSubmissions/#{sub["id"]}", { data: { type: "reviewSubmissions", id: sub["id"], attributes: { submitted: true } } })
end
puts DRY ? "Dry run finished" : "✅ Version #{VERSION} (build #{BUILD}) sent for review"
