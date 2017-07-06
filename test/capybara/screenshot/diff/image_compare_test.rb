require 'test_helper'

module Capybara
  module Screenshot
    module Diff
      class ImageCompareTest < ActionDispatch::IntegrationTest
        test 'compare class method' do
          assert ImageCompare.compare("#{TEST_IMAGES_DIR}/a.png", "#{TEST_IMAGES_DIR}/b.png")
        end

        test 'it can be instantiated' do
          assert ImageCompare.new('images/a.png', 'images/b.png')
        end

        test 'it can be instantiated with dimensions' do
          assert ImageCompare.new('images/a.png', 'images/b.png', [80, 80])
        end

        test 'compare then dimensions and cleanup' do
          comp = ImageCompare.new("#{TEST_IMAGES_DIR}/a.png", "#{TEST_IMAGES_DIR}/c.png")
          assert comp.different?
          assert_equal [11, 3, 48, 20], comp.dimensions
          ImageCompare.compare("#{TEST_IMAGES_DIR}/c.png", "#{TEST_IMAGES_DIR}/c.png")
        end

        test 'compare of 1 pixel wide diff' do
          comp = ImageCompare.new("#{TEST_IMAGES_DIR}/a.png", "#{TEST_IMAGES_DIR}/d.png")
          assert comp.different?
          assert_equal [9, 6, 9, 13], comp.dimensions
        end

        test 'compare with color_distance_limit above difference' do
          comp = ImageCompare.new("#{TEST_IMAGES_DIR}/a.png", "#{TEST_IMAGES_DIR}/b.png",
              color_distance_limit: 223)
          assert !comp.different?
          assert_equal 223, comp.max_color_distance.ceil
        end

        test 'compare with color_distance_limit below difference' do
          comp = ImageCompare.new("#{TEST_IMAGES_DIR}/a.png", "#{TEST_IMAGES_DIR}/b.png",
              color_distance_limit: 222)
          assert comp.different?
          assert_equal 223, comp.max_color_distance.ceil
        end
      end
    end
  end
end
