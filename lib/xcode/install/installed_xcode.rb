module XcodeInstall
  class InstalledXcode
    attr_reader :path
    attr_reader :version
    attr_reader :bundle_version
    attr_reader :uuid
    attr_reader :downloadable_index_url
    attr_reader :available_simulators

    def initialize(path)
      @path = Pathname.new(path)
    end

    def version
      @version ||= fetch_version
    end

    def bundle_version
      @bundle_version ||= Gem::Version.new(bundle_version_string)
    end

    def uuid
      @uuid ||= plist_entry(':DVTPlugInCompatibilityUUID')
    end

    def downloadable_index_url
      @downloadable_index_url ||= begin
        if Gem::Version.new(version) >= Gem::Version.new('8.1')
          "https://devimages-cdn.apple.com/downloads/xcode/simulators/index-#{bundle_version}-#{uuid}.dvtdownloadableindex"
        else
          "https://devimages.apple.com.edgekey.net/downloads/xcode/simulators/index-#{bundle_version}-#{uuid}.dvtdownloadableindex"
        end
      end
    end

    def approve_license
      if Gem::Version.new(version) < Gem::Version.new('7.3')
        license_path = "#{@path}/Contents/Resources/English.lproj/License.rtf"
        license_id = IO.read(license_path).match(/\bEA\d{4}\b/)
        license_plist_path = '/Library/Preferences/com.apple.dt.Xcode.plist'
        `sudo rm -rf #{license_plist_path}`
        `sudo /usr/libexec/PlistBuddy -c "add :IDELastGMLicenseAgreedTo string #{license_id}" #{license_plist_path}`
        `sudo /usr/libexec/PlistBuddy -c "add :IDEXcodeVersionForAgreedToGMLicense string #{@version}" #{license_plist_path}`
      else
        `sudo #{@path}/Contents/Developer/usr/bin/xcodebuild -license accept`
      end
    end

    def available_simulators
      @available_simulators ||= JSON.parse(`curl -Ls #{downloadable_index_url} | plutil -convert json -o - -`)['downloadables'].map do |downloadable|
        Simulator.new(downloadable)
      end
    rescue JSON::ParserError
      return []
    end

    def install_components
      # starting with Xcode 9, we have `xcodebuild -runFirstLaunch` available to do package
      # postinstalls using a documented option
      if Gem::Version.new(version) >= Gem::Version.new('9')
        `sudo #{@path}/Contents/Developer/usr/bin/xcodebuild -runFirstLaunch`
      else
        Dir.glob("#{@path}/Contents/Resources/Packages/*.pkg").each do |pkg|
          `sudo installer -pkg #{pkg} -target /`
        end
      end
      osx_build_version = `sw_vers -buildVersion`.chomp
      tools_version = `/usr/libexec/PlistBuddy -c "Print :ProductBuildVersion" "#{@path}/Contents/version.plist"`.chomp
      cache_dir = `getconf DARWIN_USER_CACHE_DIR`.chomp
      `touch #{cache_dir}com.apple.dt.Xcode.InstallCheckCache_#{osx_build_version}_#{tools_version}`
    end

    # This method might take a few ms, this could be improved by implementing https://github.com/KrauseFx/xcode-install/issues/273
    def fetch_version
      output = `DEVELOPER_DIR='' "#{@path}/Contents/Developer/usr/bin/xcodebuild" -version`
      return '0.0' if output.nil? || output.empty? # ¯\_(ツ)_/¯
      output.split("\n").first.split(' ')[1]
    end

    :private

    def bundle_version_string
      digits = plist_entry(':DTXcode').to_i.to_s
      if digits.length < 3
        digits.split(//).join('.')
      else
        "#{digits[0..-3]}.#{digits[-2]}.#{digits[-1]}"
      end
    end

    def plist_entry(keypath)
      `/usr/libexec/PlistBuddy -c "Print :#{keypath}" "#{path}/Contents/Info.plist"`.chomp
    end
  end
end
