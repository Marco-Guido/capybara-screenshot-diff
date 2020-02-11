# frozen_string_literal: true

require_relative 'os'

module Capybara
  module Screenshot
    module Diff
      module Stabilization
        include Os

        IMAGE_WAIT_SCRIPT = <<-JS.strip_heredoc.freeze
          function pending_image() {
            var images = document.images;
            for (var i = 0; i < images.length; i++) {
              if (!images[i].complete) {
                  return images[i].src;
              }
            }
            return false;
          }()
        JS

        def take_simple_screenshot(comparison, color_distance_limit:, shift_distance_limit:,
                                   area_size_limit:, skip_area:, stability_time_limit:, wait:, save_mode:)  #Added by Progenda
          blurred_input = prepare_page_for_screenshot(timeout: wait)
          #puts("taking screenshot")
          take_right_size_screenshot(comparison)
          if ! save_mode
            puts("Checking diff")
            is_different = save_diff(comparison)
            return is_different
          end
        ensure
          blurred_input&.click
        end

        def take_stable_screenshot(comparison, color_distance_limit:, shift_distance_limit:,
            area_size_limit:, skip_area:, stability_time_limit:, wait:)
          blurred_input = prepare_page_for_screenshot(timeout: wait)
          previous_file_name = comparison.old_file_name
          screenshot_started_at = last_image_change_at = Time.now
          1.step do |i|
            take_right_size_screenshot(comparison)

            break unless stability_time_limit

            if comparison.quick_equal?
              clean_stabilization_images(comparison.new_file_name)
              break
            end
            comparison.reset

            if previous_file_name
              stabilization_comparison =
                ImageCompare.new(comparison.new_file_name, previous_file_name,
                    color_distance_limit: color_distance_limit, shift_distance_limit: shift_distance_limit,
                    area_size_limit: area_size_limit, skip_area: skip_area)
              if stabilization_comparison.quick_equal?
                if (Time.now - last_image_change_at) > stability_time_limit
                  clean_stabilization_images(comparison.new_file_name)
                  break
                end
                next
              else
                last_image_change_at = Time.now
              end
            end

            previous_file_name = "#{comparison.new_file_name.chomp('.png')}" \
                "_x#{format('%02i', i)}_#{(Time.now - screenshot_started_at).round(1)}s" \
                "_#{stabilization_comparison.dimensions&.to_s&.gsub(', ', '_') || :initial}.png~"
            FileUtils.mv comparison.new_file_name, previous_file_name

            check_max_wait_time(comparison, screenshot_started_at,
                wait: wait, shift_distance_limit: shift_distance_limit)
          end
        ensure
          blurred_input&.click
        end

        private

        def reduce_retina_image_size(file_name)
          return if !ON_MAC || !selenium? || !Capybara::Screenshot.window_size

          saved_image = ChunkyPNG::Image.from_file(file_name)
          width = Capybara::Screenshot.window_size[0]
          return if saved_image.width < width * 2

          unless @_csd_retina_warned
            warn 'Halving retina screenshot.  ' \
                'You should add "force-device-scale-factor=1" to your Chrome chromeOptions args.'
            @_csd_retina_warned = true
          end
          height = (width * saved_image.height) / saved_image.width
          resized_image = saved_image.resample_bilinear(width, height)
          resized_image.save(file_name)
        end

        def stabilization_images(base_file)
          Dir["#{base_file.chomp('.png')}_x*.png~"].sort
        end

        def clean_stabilization_images(base_file)
          FileUtils.rm stabilization_images(base_file)
        end

        def prepare_page_for_screenshot(timeout:)
          assert_images_loaded(timeout: timeout)
          if Capybara::Screenshot.blur_active_element
            active_element = execute_script(<<-JS)
              ae = document.activeElement;
              if (ae.nodeName == "INPUT" || ae.nodeName == "TEXTAREA") {
                  ae.blur();
                  return ae;
              }
              return null;
            JS
            blurred_input = page.driver.send :unwrap_script_result, active_element
          end
          execute_script("$('*').css('caret-color','transparent')") if Capybara::Screenshot.hide_caret
          blurred_input
        end

        def take_right_size_screenshot(comparison)
          save_screenshot(comparison.new_file_name)

          # TODO(uwe): Remove when chromedriver takes right size screenshots
          reduce_retina_image_size(comparison.new_file_name)
          # ODOT
        end

        def save_diff(comparison) #Added by Progenda
          stabilization_comparison = ImageCompare.new(comparison.new_file_name, comparison.old_file_name,
                                                      color_distance_limit: comparison.color_distance_limit,
                                                      shift_distance_limit: comparison.shift_distance_limit,
                                                      area_size_limit: comparison.area_size_limit, skip_area: comparison.skip_area)
          return stabilization_comparison.different?
        end

        def clean_files(comparison, deep: false) #Added by Progenda
          if File.exist?(comparison.annotated_new_file_name)
            FileUtils.cp comparison.annotated_new_file_name, comparison.new_file_name
            File.delete(comparison.annotated_new_file_name)
          end
          if File.exist?(comparison.annotated_old_file_name)
            File.delete(comparison.annotated_old_file_name)
          end
          if deep
            File.delete(comparison.new_file_name)
          end
        end

        def check_max_wait_time(comparison, screenshot_started_at, wait:, shift_distance_limit:)
          shift_factor = shift_distance_limit ? (shift_distance_limit * 2 + 1) ^ 2 : 1
          max_wait_time = wait * shift_factor
          return if (Time.now - screenshot_started_at) < max_wait_time

          # FIXME(uwe): Change to store the failure and only report if the test succeeds functionally.
          previous_file = comparison.old_file_name
          stabilization_images(comparison.new_file_name).each do |file_name|
            if File.exist? previous_file
              stabilization_comparison =
                ImageCompare.new(file_name, previous_file,
                    color_distance_limit: comparison.color_distance_limit,
                    shift_distance_limit: comparison.shift_distance_limit,
                    area_size_limit: comparison.area_size_limit, skip_area: comparison.skip_area)
              assert stabilization_comparison.different?
              FileUtils.mv stabilization_comparison.annotated_new_file_name, file_name
              FileUtils.rm stabilization_comparison.annotated_old_file_name
            end
            previous_file = file_name
          end
          fail("Could not get stable screenshot within #{max_wait_time}s\n" \
                    "#{stabilization_images(comparison.new_file_name).join("\n")}")
        end

        def assert_images_loaded(timeout:)
          return unless respond_to? :evaluate_script

          start = Time.now
          loop do
            pending_image = evaluate_script IMAGE_WAIT_SCRIPT
            break unless pending_image

            assert((Time.now - start) < timeout,
                "Images not loaded after #{timeout}s: #{pending_image.inspect}")
            sleep 0.1
          end
        end
      end
    end
  end
end
