require 'faraday'
require 'faraday_middleware'
require 'spyke/config'
require 'spyke/path'
require 'spyke/result'
require 'spyke/normalized_validation_error'

module Spyke
  module Http
    extend ActiveSupport::Concern
    METHODS = %i{ get post put patch delete }

    included do
      class_attribute :connection, instance_accessor: false
    end

    module ClassMethods
      METHODS.each do |method|
        define_method(method) do
          new_instance_or_collection_from_result scoped_request(method)
        end
      end

      def request(method, path, params = {})
        ActiveSupport::Notifications.instrument('request.spyke', method: method) do |payload|
          response = send_request(method, path, params)
          
          token_proc = Proc.new do |response|
            if response.status == 401
              meth = connection.headers[:token_generator].split(',')
              # tkn = .Gluu::Auth.get_scim_token
              tkn = meth[0].constantize.send(meth[1])
              connection.headers['Authorization'] = "Bearer #{tkn}"
              response = send_request(method, path, params)
              token_proc.call(response)
            else
              response
            end 
          end

          response = token_proc.call(response)
          payload[:url], payload[:status] = response.env.url, response.status
          Result.new_from_response(response)
        end
      end

      def new_instance_from_result(result)
        new_or_return result.data if result.data
      end

      def new_collection_from_result(result)
        Collection.new Array(result.data).map { |record| new_or_return(record) }, result.metadata
      end

      def uri(uri_template = nil)
        @uri ||= uri_template || default_uri
      end

      private

        def send_request(method, path, params)
          connection.send(method) do |request|
            if method == :get
              params.delete(:relation_ids)
              request.url path.to_s, params
            else
              request.url path.to_s
              request.body = params
            end
          end
          rescue Faraday::ConnectionFailed, Faraday::TimeoutError
            raise ConnectionError
        end

        def scoped_request(method, id=nil)
          uri = new.uri(id)
          params = current_scope.params.except(*uri.variables)
          request(method, uri, params)
        end

        def new_instance_or_collection_from_result(result)
          if result.data.is_a?(Array)
            new_collection_from_result(result)
          else
            new_instance_from_result(result)
          end
        end

        def new_or_return(attributes_or_object)
          if attributes_or_object.is_a?(Spyke::Base)
            attributes_or_object
          else
            new attributes_or_object
          end
        end

        def default_uri
          "#{model_name.element.pluralize}(/:#{primary_key})"
        end
    end

    METHODS.each do |method|
      define_method(method) do |action = nil, params = {}|
        params = action if action.is_a?(Hash)
        path = resolve_path_from_action(action)
        result = self.class.request(method, path, params)

        add_errors_to_model(result.errors)
        self.attributes = result.data
      end
    end

    def uri(id=nil)
      attributes[:id] = id unless id.nil?
      Path.new(@uri_template, attributes) if @uri_template
    end

    private

      def add_errors_to_model(errors_hash)
        errors_hash.each do |field, field_errors|
          field_errors.each do |error_attributes|
            error = NormalizedValidationError.new(error_attributes)
            errors.add(field.to_sym, error.message, error.options)
          end
        end
      end

      def resolve_path_from_action(action)
        case action
        when Symbol then uri.join(action)
        when String then Path.new(action, attributes)
        else uri
        end
      end
  end
end
