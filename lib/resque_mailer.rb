require 'resque_mailer/version'

module Resque
  module Mailer
    class << self
      attr_accessor :default_queue_name, :default_queue_target, :current_env
      attr_reader :excluded_environments

      def excluded_environments=(envs)
        @excluded_environments = [*envs].map { |e| e.to_sym }
      end

      def included(base)
        base.extend(ClassMethods)
      end
    end

    self.default_queue_target = ::Resque
    self.default_queue_name = "mailer"
    self.excluded_environments = [:test]

    module ClassMethods
      def current_env
        if defined?(Rails)
          ::Resque::Mailer.current_env || ::Rails.env
        else
          ::Resque::Mailer.current_env
        end
      end

      def method_missing(method_name, *args)
        return super if environment_excluded?
        
        if action_methods.include?(method_name.to_s)
          MessageDecoy.new(self, method_name, *args)
        else
          super
        end
      end

      def perform(action, *args)
        self.send(:new, action, *args).message.deliver
      end

      def environment_excluded?
        puts current_env.inspect

        !ActionMailer::Base.perform_deliveries || excluded_environment?(current_env)
      end

      def queue
        @queue || ::Resque::Mailer.default_queue_name
      end

      def queue=(name)
        @queue = name
      end

      def resque
        ::Resque::Mailer.default_queue_target
      end

      def excluded_environment?(name)
        ::Resque::Mailer.excluded_environments && ::Resque::Mailer.excluded_environments.include?(name.try(:to_sym))
      end

      def deliver?
        true
      end
    end

    class MessageDecoy
      delegate :to_s, :to => :actual_message

      def initialize(mailer_class, method_name, *args)
        @mailer_class = mailer_class
        @method_name = method_name
        *@args = *args
      end

      def resque
        ::Resque::Mailer.default_queue_target
      end

      def actual_message
        @actual_message ||= @mailer_class.send(:new, @method_name, *@args).message
      end

      def deliver
        if @mailer_class.deliver?
          resque.enqueue(@mailer_class, @method_name, *@args)
        end
      end

      def deliver_at(time)
        puts @mailer_class.environment_excluded?

        return deliver! if @mailer_class.environment_excluded?

        unless resque.respond_to? :enqueue_at
          raise "You need to install resque-scheduler to use deliver_at"
        end

        if @mailer_class.deliver?
          resque.enqueue_at(time, @mailer_class, @method_name, *@args)
        end
      end

      def deliver_in(time)
        return deliver! if @mailer_class.environment_excluded?

        unless resque.respond_to? :enqueue_in
          raise "You need to install resque-scheduler to use deliver_in"
        end

        if @mailer_class.deliver?
          resque.enqueue_in(time, @mailer_class, @method_name, *@args)
        end
      end

      def deliver!
        actual_message.deliver!
      end

      def method_missing(method_name, *args)
        actual_message.send(method_name, *args)
      end
    end
  end
end
