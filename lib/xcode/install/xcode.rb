module XcodeInstall
  # A version of Xcode we fetched from the Apple Developer Portal
  # we can download & install.
  #
  # Sample object:
  # <XcodeInstall::Xcode:0x007fa1d451c390
  #    @date_modified=2015,
  #    @name="6.4",
  #    @path="/Developer_Tools/Xcode_6.4/Xcode_6.4.dmg",
  #    @url=
  #     "https://developer.apple.com/devcenter/download.action?path=/Developer_Tools/Xcode_6.4/Xcode_6.4.dmg",
  #    @version=Gem::Version.new("6.4")>,
  class Xcode
    attr_reader :date_modified

    # The name might include extra information like "for Lion" or "beta 2"
    attr_reader :name
    attr_reader :path
    attr_reader :url
    attr_reader :version
    attr_reader :release_notes_url

    # Accessor since it's set by the `Installer`
    attr_accessor :installed

    alias installed? installed

    def initialize(json, url = nil, release_notes_url = nil)
      if url.nil?
        @date_modified = json['dateModified'].to_i
        @name = json['name'].gsub(/^Xcode /, '')
        @path = json['files'].first['remotePath']
        url_prefix = 'https://developer.apple.com/devcenter/download.action?path='
        @url = "#{url_prefix}#{@path}"
        @release_notes_url = "#{url_prefix}#{json['release_notes_path']}" if json['release_notes_path']
      else
        @name = json
        @path = url.split('/').last
        url_prefix = 'https://developer.apple.com/'
        @url = "#{url_prefix}#{url}"
        @release_notes_url = "#{url_prefix}#{release_notes_url}"
      end

      begin
        @version = Gem::Version.new(@name.split(' ')[0])
      rescue
        @version = Installer::MINIMUM_VERSION
      end
    end

    def to_s
      "Xcode #{version} -- #{url}"
    end

    def ==(other)
      date_modified == other.date_modified && name == other.name && path == other.path && \
        url == other.url && version == other.version
    end

    def self.new_prerelease(version, url, release_notes_path)
      new('name' => version,
          'files' => [{ 'remotePath' => url.split('=').last }],
          'release_notes_path' => release_notes_path)
    end
  end
end
