module Seek
  module Dois
    module DoiGeneration
      extend ActiveSupport::Concern

      included do
        def self.supports_doi?
          true
        end

        searchable(auto_index: false) do
          text :doi
        end
      end

      # TODO
      # is_published && can_manage
      # after one week asset is created
      # asset type
      # is_doi_already minted
      def is_doiable?(version)
        supports_doi? && Seek::Config.doi_minting_enabled && can_manage? && is_published? && !is_doi_minted?(version) && !is_doi_time_locked?
      end

      def is_doi_minted?(version)
        asset_version = find_version version
        !asset_version.doi.blank?
      end

      def latest_citable_doi
        return nil unless has_doi?
        versions.where('doi IS NOT NULL').last.doi
      end

      def has_doi?
        versions.where('doi IS NOT NULL').compact.any?
      end

      # minting doi is locked until configuration days since the asset is created
      def is_doi_time_locked?
        time = Seek::Config.time_lock_doi_for || 0
        (created_at + time.to_i.days) > Time.now
      end

      def state_allows_delete?(*args)
        if supports_doi?
          !has_doi? && super
        else
          super
        end
      end

      def generated_doi(version = nil)
        prefix = Seek::Config.doi_prefix.to_s + '/'
        suffix = Seek::Config.doi_suffix.to_s + '.'
        suffix << self.class.name.downcase + '.' + id.to_s
        suffix << '.' + version.to_s if version
        prefix + suffix
      end
    end
  end
end

ActiveRecord::Base.class_eval do
  def self.supports_doi?
    false
  end

  def supports_doi?
    self.class.supports_doi?
  end
end
