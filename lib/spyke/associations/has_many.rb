module Spyke
  module Associations
    class HasMany < Association
      def initialize(*args)
	      super
        ids = get_relation_ids()
        @params[:relation_ids] = ids
      end

      def load
        self
      end

      def assign_nested_attributes(incoming)
        incoming = incoming.values if incoming.is_a?(Hash)
        combined_attributes = combine_with_existing(incoming)
        clear_existing!
        combined_attributes.each do |attributes|
          build(attributes)
        end
      end

      private

        def get_relation_ids
          relation_field = @options[:relation_field]
          field = parent.attributes[relation_field.to_s]
          field.map{|i| i['value']}
        end

        def parent_path
          parent.class.model_name.element.pluralize
        end

        def combine_with_existing(incoming)
          return incoming unless primary_keys_present_in_existing?
          combined = embedded_attributes + incoming
          group_by_primary_key(combined).flat_map do |primary_key, hashes|
            if primary_key.present?
              hashes.reduce(:merge)
            else
              hashes
            end
          end
        end

        def group_by_primary_key(array)
          array.group_by { |h| h.with_indifferent_access[primary_key].to_s }
        end

        def primary_keys_present_in_existing?
          embedded_attributes && embedded_attributes.any? { |attr| attr.has_key?(primary_key) }
        end

        def clear_existing!
          update_parent []
        end

        def embedded_attributes
          @embedded_attributes ||= parent.attributes.to_params[name]
        end

        def add_to_parent(record)
          parent.attributes[name] ||= []
          parent.attributes[name] << record
          record
        end
    end
  end
end
