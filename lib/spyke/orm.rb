module Spyke
  module Orm
    extend ActiveSupport::Concern

    included do
      define_model_callbacks :create, :update, :save, :destroy

      class_attribute :include_root
      self.include_root = true

      class_attribute :callback_methods, instance_accessor: false
      self.callback_methods = { create: :post, update: :put }.freeze

      class_attribute :primary_key
      self.primary_key = :id
    end

    module ClassMethods
      def include_root_in_json(value)
        self.include_root = value
      end

      def method_for(callback, value = nil)
        self.callback_methods = callback_methods.merge(callback => value) if value
        callback_methods[callback]
      end

      def find(id)
        raise ResourceNotFound if id.blank?
        where(primary_key => id).find_one || raise(ResourceNotFound)
      end

      def fetch
         if current_scope.params[:relation_ids]
            result = []
            current_scope.params[:relation_ids].each do |id|
              result << scoped_request(:get, id)
            end
            response = Struct.new(:data, :metadata, :errors)
            response = response.new(
              result.map{|i| i.body['data']},
              result.first.try(:body).try(:[], 'metadata') ,
              result.map{|i| i.body['errors']},
            )
        else
          scoped_request :get
        end
      end

      def create(attributes = {})
        record = new(attributes)
        record.save
        record
      end

      def destroy(id = nil)
        new(primary_key => id).destroy
      end
    end

    def to_params
      params_not_embedded_in_url
    end

    def persisted?
      id?
    end

    def save
      run_callbacks :save do
        callback = persisted? ? :update : :create
        run_callbacks(callback) do
          send self.class.method_for(callback), to_params
        end
      end
    end

    def destroy
      self.attributes = delete
    end

    def update(new_attributes)
      self.attributes = new_attributes
      save
    end
    alias :update_attributes :update

    def reload
      self.attributes = self.class.find(id).attributes
    end

    private

      def param_root
        if [String, Symbol].include?(include_root.class)
          include_root.to_s
        elsif include_root?
          self.class.model_name.param_key
        end
      end

      def params_not_embedded_in_url
        attributes.to_params.except(*uri.variables)
      end
  end
end
