require 'fileutils'

module ImageResizer
  class ImageProcessor
    def initialize(source)
      @img = Magick::Image.read(source).first
    end

    def constrain_width(width)
      if @img.columns == 0
        raise ProcessingError.new("The width of the image #{source} is 0")
      end

      resize_image_by_width(width)
    end

    def constrain_height(height)
      if @img.rows == 0
        raise ProcessingError.new("The height of the image #{source} is 0")
      end

      resize_image_by_height(height)
    end

    def resize_by_max(size)
      if @img.rows > @img.columns # portrait
        constrain_height(size)
      else # landscape
        constrain_width(size)
      end
    end

    def resize_and_crop(width, height)
      if @img.rows == 0
        raise ProcessingError.new("The height of the image #{source} is 0")
      end

      original_ratio = @img.columns.to_f / @img.rows.to_f
      target_ratio = width.to_f / height.to_f

      resized = if target_ratio > original_ratio
                  resize_image_by_width(width)
                else
                  resize_image_by_height(height)
                end
      resized.crop(Magick::CenterGravity, width, height)
    end

    private

    def resize_image_by_width(width)
      scale_factor = width.to_f / @img.columns.to_f
      @img.resize(scale_factor)
    end

    def resize_image_by_height(height)
      scale_factor = height.to_f / @img.rows.to_f
      @img.resize(scale_factor)
    end

    class ProcessingError < StandardError; end
  end
end
