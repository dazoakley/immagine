require 'sinatra/base'
require 'json'

module ImageResizer
  class Service < Sinatra::Base
    DEFAULT_IMAGE_QUALITY = 85

    before do
      http_headers = request.env.dup.select { |key, _val| key =~ /\AHTTP_/ }
      http_headers.delete('HTTP_COOKIE')

      ImageResizer.logger.error 'HTTP HEADERS:'
      ImageResizer.logger.error http_headers
    end

    get '/heartbeat' do
      'ok'
    end

    get %r{\A(.+)?/([^/]+)/([^/]+)\z} do |dir, format_code, basename|
      # check we have a dir
      if dir.to_s.empty?
        log_error('404, incorrect path, dir not extracted.')
        statsd.increment('dir_not_extracted')
        not_found
      end

      # check to see if this is an *actual* filepath
      static_file = File.join(ImageResizer.settings['source_folder'], dir, format_code, basename)

      if File.exist?(static_file)
        etag calculate_etags(dir, format_code, basename, static_file)
        set_cache_control_headers(request, dir)

        statsd.increment('serve_original_image')
        send_file static_file
      end

      # check the format_code is on the whitelist
      unless ImageResizer.settings['size_whitelist'].include?(format_code)
        log_error("404, format code not found (#{format_code}).")
        statsd.increment('asset_format_not_in_whitelist')
        not_found
      end

      source_file = File.join(ImageResizer.settings['source_folder'], dir, basename)

      # check the file exists
      unless File.exist?(source_file)
        log_error("404, original file not found (#{source_file}).")
        statsd.increment('asset_not_found')
        not_found
      end

      # etags & cache headers
      etag calculate_etags(dir, format_code, basename, source_file)
      last_modified File.mtime(source_file)
      set_cache_control_headers(request, dir)

      # generate image
      image = statsd.time('asset_resize_request') do
        process_image(source_file, format_code)
      end

      # content type
      content_type image.mime_type

      # image quality
      image_quality = Integer(request.env['HTTP_X_IMAGE_QUALITY'] || DEFAULT_IMAGE_QUALITY)

      image.to_blob { self.quality = image_quality }
    end

    private

    def set_cache_control_headers(request, dir)
      if custom_cache_control = request.env['HTTP_X_CACHE_CONTROL']
        cache_control custom_cache_control
      elsif dir =~ %r{\A/live}
        cache_control :public, max_age: 86400
      else
        cache_control :private, max_age: 0
      end
    end

    def process_image(path, format)
      processor = ImageProcessor.new(path)

      image = case format
              when /\Aw(\d+)\z/
                processor.constrain_width(Regexp.last_match[1].to_i)
              when /\Ah(\d+)\z/
                processor.constrain_height(Regexp.last_match[1].to_i)
              when /\Am(\d+)\z/
                processor.resize_by_max(Regexp.last_match[1].to_i)
              when /\Aw(\d+)h(\d+)\z/
                processor.resize_and_crop(Regexp.last_match[1].to_i, Regexp.last_match[2].to_i)
              when /\Arelative\z/
                processor.resize_relative_to_original
              else
                fail "Unsupported format: #{format}. Please remove it from the whitelist."
              end

      image.strip!
      image
    end

    def calculate_etags(dir, format_code, basename, source_file)
      factors = [
        dir,
        format_code,
        basename,
        File.mtime(source_file)
      ].to_json

      Digest::MD5.hexdigest(factors)
    end

    def log_error(msg)
      logger.error("[ImageResizer::Service] (#{request.path}) - #{msg}")
    end

    def logger
      ImageResizer.logger
    end

    def statsd
      ImageResizer.statsd
    end
  end
end