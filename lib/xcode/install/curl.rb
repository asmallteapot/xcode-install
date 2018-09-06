module XcodeInstall
  class Curl
    COOKIES_PATH = Pathname.new('/tmp/curl-cookies.txt')

    # @param url: The URL to download
    # @param directory: The directory to download this file into
    # @param cookies: Any cookies we should use for the download (used for auth with Apple)
    # @param output: A PathName for where we want to store the file
    # @param progress: parse and show the progress?
    # @param progress_block: A block that's called whenever we have an updated progress %
    #                        the parameter is a single number that's literally percent (e.g. 1, 50, 80 or 100)
    # rubocop:disable Metrics/AbcSize
    def fetch(url: nil,
              directory: nil,
              cookies: nil,
              output: nil,
              progress: nil,
              progress_block: nil)
      options = cookies.nil? ? [] : ['--cookie', cookies, '--cookie-jar', COOKIES_PATH]

      uri = URI.parse(url)
      output ||= File.basename(uri.path)
      output = (Pathname.new(directory) + Pathname.new(output)) if directory

      # Piping over all of stderr over to a temporary file
      # the file content looks like this:
      #  0 4766M    0 6835k    0     0   573k      0  2:21:58  0:00:11  2:21:47  902k
      # This way we can parse the current %
      # The header is
      #  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
      #
      # Discussion for this on GH: https://github.com/KrauseFx/xcode-install/issues/276
      # It was not easily possible to reimplement the same system using built-in methods
      # especially when it comes to resuming downloads
      # Piping over stderror to Ruby directly didn't work, due to the lack of flushing
      # from curl. The only reasonable way to trigger this, is to pipe things directly into a
      # local file, and parse that, and just poll that. We could get real time updates using
      # the `tail` command or similar, however the download task is not time sensitive enough
      # to make this worth the extra complexity, that's why we just poll and
      # wait for the process to be finished
      progress_log_file = File.join(CACHE_DIR, "progress.#{Time.now.to_i}.progress")
      FileUtils.rm_f(progress_log_file)

      retry_options = ['--retry', '3']
      command = [
        'curl',
        *options,
        *retry_options,
        '--location',
        '--continue-at',
        '-',
        '--output',
        output,
        url
      ].map(&:to_s)

      command_string = command.collect(&:shellescape).join(' ')
      command_string += " 2> #{progress_log_file}" # to not run shellescape on the `2>`

      # Run the curl command in a loop, retry when curl exit status is 18
      # "Partial file. Only a part of the file was transferred."
      # https://curl.haxx.se/mail/archive-2008-07/0098.html
      # https://github.com/KrauseFx/xcode-install/issues/210
      3.times do
        # Non-blocking call of Open3
        # We're not using the block based syntax, as the bacon testing
        # library doesn't seem to support writing tests for it
        stdin, stdout, stderr, wait_thr = Open3.popen3(command_string)

        # Poll the file and see if we're done yet
        while wait_thr.alive?
          sleep(0.5) # it's not critical for this to be real-time
          next unless File.exist?(progress_log_file) # it might take longer for it to be created

          progress_content = File.read(progress_log_file).split("\r").last

          # Print out the progress for the CLI
          if progress
            print "\r#{progress_content}%"
            $stdout.flush
          end

          # Call back the block for other processes that might be interested
          matched = progress_content.match(/^\s*(\d+)/)
          next unless matched.length == 2
          percent = matched[1].to_i
          progress_block.call(percent) if progress_block
        end

        # as we're not making use of the block-based syntax
        # we need to manually close those
        stdin.close
        stdout.close
        stderr.close

        return wait_thr.value.success? if wait_thr.value.success?
      end
      false
    ensure
      FileUtils.rm_f(COOKIES_PATH)
      FileUtils.rm_f(progress_log_file)
    end
  end
end
