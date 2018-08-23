require "active_support/core_ext/module/delegation"
require "active_support/core_ext/object/blank"

module Administrate
  class Search
    def initialize(scoped_resource, dashboard_class, term)
      @dashboard_class = dashboard_class
      @scoped_resource = scoped_resource
      @term = term
    end

    def run
      if @term.blank?
        @scoped_resource.all
      else
        @scoped_resource.joins(tables_to_join).where(query, *search_terms)
      end
    end

    private

    def query
      search_attributes.map do |attr|
        table_name = query_table_name(attr)
        searchable_fields(attr).map do |field|
          attr_name = column_to_query(field)
          "LOWER(CAST(#{table_name}.#{attr_name} AS CHAR(256))) LIKE ?"
        end.join(" OR ")
      end.join(" OR ")
    end

    def searchable_fields(attr)
      return [attr] unless association_search?(attr)
      attribute_types[attr].searchable_fields
    end

    def search_terms
      fields_count = search_attributes.sum do |attr|
        searchable_fields(attr).count
      end
      ["%#{term.mb_chars.downcase}%"] * fields_count
    end

    def search_attributes
      attribute_types.keys.select do |attribute|
        attribute_types[attribute].searchable?
      end
    end

    def attribute_types
      @dashboard_class::ATTRIBUTE_TYPES
    end

    def query_table_name(attr)
      if association_search?(attr)
        class_name = attribute_types[attr].options.
          fetch(:class_name, attr.to_s.singularize.camelcase)
        ActiveRecord::Base.connection.
          quote_table_name(class_name.constantize.table_name)
      else
        ActiveRecord::Base.connection.
          quote_table_name(@scoped_resource.table_name)
      end
    end

    def column_to_query(attr)
      ActiveRecord::Base.connection.quote_column_name(attr)
    end

    def tables_to_join
      attribute_types.keys.select do |attribute|
        attribute_types[attribute].searchable? && association_search?(attribute)
      end
    end

    def association_search?(attribute)
      return unless attribute_types[attribute].respond_to?(:deferred_class)

      [
        Administrate::Field::BelongsTo,
        Administrate::Field::HasMany,
        Administrate::Field::HasOne,
      ].include?(attribute_types[attribute].deferred_class)
    end

    attr_reader :resolver, :term
  end
end
