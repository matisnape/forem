module Admin
  class ConfigsController < Admin::ApplicationController
    CAMPAIGN_PARAMS =
      %i[
        campaign_featured_tags
        campaign_hero_html_variant_name
        campaign_sidebar_enabled
        campaign_sidebar_image
        campaign_url
        campaign_articles_require_approval
      ].freeze

    COMMUNITY_PARAMS =
      %i[
        community_name
        community_description
        community_member_label
        community_copyright_start_year
        staff_user_id
        tagline
      ].freeze

    NEWSLETTER_PARAMS =
      %i[
        mailchimp_api_key
        mailchimp_community_moderators_id
        mailchimp_newsletter_id
        mailchimp_sustaining_members_id
        mailchimp_tag_moderators_id
      ].freeze

    RATE_LIMIT_PARAMS =
      %i[
        rate_limit_comment_creation
        rate_limit_email_recipient
        rate_limit_follow_count_daily
        rate_limit_image_upload
        rate_limit_published_article_creation
        rate_limit_published_article_antispam_creation
        rate_limit_organization_creation
        rate_limit_user_subscription_creation
        rate_limit_article_update
        rate_limit_user_update
        rate_limit_feedback_message_creation
        rate_limit_listing_creation
        rate_limit_reaction_creation
        rate_limit_send_email_confirmation
      ].freeze

    MASCOT_PARAMS =
      %i[
        mascot_image_description
        mascot_image_url
        mascot_footer_image_url
        mascot_footer_image_width
        mascot_footer_image_height
        mascot_user_id
      ].freeze

    IMAGE_PARAMS =
      %i[
        favicon_url
        logo_png
        logo_svg
        main_social_image
        secondary_logo_url
        left_navbar_svg_icon
        right_navbar_svg_icon
      ].freeze

    ONBOARDING_PARAMS =
      %i[
        onboarding_logo_image
        onboarding_background_image
        onboarding_taskcard_image
        suggested_tags
        suggested_users
      ].freeze

    JOB_PARAMS =
      %i[
        jobs_url
        display_jobs_banner
      ].freeze

    ALLOWED_EMPTY_ENUMERABLES =
      %i[
        authentication_providers
      ].freeze

    ALLOWED_PARAMS =
      %i[
        ga_tracking_id
        periodic_email_digest_max
        periodic_email_digest_min
        sidebar_tags
        twitter_hashtag
        shop_url
        payment_pointer
        stripe_api_key
        stripe_publishable_key
        health_check_token
        feed_style
        feed_strategy
        default_font
        sponsor_headline
        public
        twitter_key
        twitter_secret
        github_key
        github_secret
        facebook_key
        facebook_secret
        invite_only_mode
        allow_email_password_registration
        allow_email_password_login
        primary_brand_color_hex
        spam_trigger_terms
        recaptcha_site_key
        recaptcha_secret_key
        video_encoder_key
      ].freeze

    layout "admin"

    before_action :extra_authorization_and_confirmation, only: [:create]
    before_action :validate_inputs, only: [:create]

    def show
      @confirmation_text = confirmation_text
    end

    def create
      clean_up_params

      config_params.each do |key, value|
        if value.is_a?(Array)
          update_siteconfig_with_array(key, value)
        elsif value.respond_to?(:to_h)
          SiteConfig.public_send("#{key}=", value.to_h) unless value.empty?
        else
          SiteConfig.public_send("#{key}=", value.strip) unless value.nil?
        end
      end

      bust_relevant_caches
      redirect_to admin_config_path, notice: "Site configuration was successfully updated."
    end

    private

    def confirmation_text
      "My username is @#{current_user.username} and this action is 100% safe and appropriate."
    end

    def config_params
      all_params = ALLOWED_PARAMS |
        CAMPAIGN_PARAMS |
        COMMUNITY_PARAMS |
        NEWSLETTER_PARAMS |
        RATE_LIMIT_PARAMS |
        MASCOT_PARAMS |
        IMAGE_PARAMS |
        ONBOARDING_PARAMS |
        JOB_PARAMS

      has_emails = params.dig(:site_config, :email_addresses).present?
      params[:site_config][:email_addresses][:default] = ApplicationConfig["DEFAULT_EMAIL"] if has_emails
      params&.require(:site_config)&.permit(
        all_params,
        authentication_providers: [],
        social_media_handles: SiteConfig.social_media_handles.keys,
        email_addresses: SiteConfig.email_addresses.keys,
        meta_keywords: SiteConfig.meta_keywords.keys,
        credit_prices_in_cents: SiteConfig.credit_prices_in_cents.keys,
      )&.with_defaults(authentication_providers: [])
    end

    def raise_confirmation_mismatch_error
      raise ActionController::BadRequest.new, "The confirmation key does not match"
    end

    def extra_authorization_and_confirmation
      not_authorized unless current_user.has_role?(:single_resource_admin, Config) # Special additional permission
      raise_confirmation_mismatch_error if params.require(:confirmation) != confirmation_text
    end

    def validate_inputs
      errors = []
      errors << "Brand color must be darker for accessibility." if brand_contrast_too_low
      errors << "Brand color must be be a 6 character hex (starting with #)." if brand_color_not_hex
      redirect_to admin_config_path, alert: "😭 #{errors.join(',')}" if errors.any?
    end

    def clean_up_params
      config = params[:site_config]
      return unless config

      %i[sidebar_tags suggested_tags suggested_users].each do |param|
        config[param] = config[param]&.downcase&.delete(" ") if config[param]
      end
      config[:credit_prices_in_cents]&.transform_values!(&:to_i)
    end

    def bust_relevant_caches
      CacheBuster.bust("/tags/onboarding") # Needs to change when suggested_tags is edited.
      CacheBuster.bust("/shell_top") # Cached at edge, sent to service worker.
      CacheBuster.bust("/shell_bottom") # Cached at edge, sent to service worker.
      CacheBuster.bust("/onboarding") # Page is cached at edge.
      CacheBuster.bust("/") # Page is cached at edge.
      Rails.cache.delete_matched("*-#{ApplicationConfig['RELEASE_FOOTPRINT']}") # Delete all caches tied to this key.
    end

    # Validations
    def brand_contrast_too_low
      hex = params.dig(:site_config, :primary_brand_color_hex)
      hex.present? && Color::Accessibility.new(hex).low_contrast?
    end

    def brand_color_not_hex
      hex = params.dig(:site_config, :primary_brand_color_hex)
      hex.present? && !hex.match?(/\A#(\h{6}|\h{3})\z/)
    end

    def update_siteconfig_with_array(key, value)
      return if value.empty? && ALLOWED_EMPTY_ENUMERABLES.exclude?(key.to_sym)

      SiteConfig.public_send("#{key}=", value.reject(&:blank?))
    end
  end
end
