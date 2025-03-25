class ActiveRecordAutoValidations::AutoValidateModelClass
  attr_reader :ignore_column_names, :model_class

  def self.execute!(...)
    ActiveRecordAutoValidations::AutoValidateModelClass.new(...).perform
  end

  def initialize(model_class:, ignore_column_names: [])
    @ignore_column_names = ignore_column_names
    @model_class = model_class
  end

  def perform
    check_if_already_loaded_on_model_class!
    register_loaded_on_model_class!

    begin
      columns
      indexes
    rescue ActiveRecord::StatementInvalid => e
      # Database is probably not running - we need to ignore this to make stuff like db:migrate, db:schema:load work
      Rails.logger.info { "AutoValidate: Ignoring error while loading columns, because database might not be initialized: #{e.message}" }
      return
    end

    insert_active_record_auto_validations_from_columns!
    insert_active_record_auto_validations_from_indexes!
  end

  def check_if_already_loaded_on_model_class!
    auto_validations_loaded = model_class.instance_variable_get(:@_active_record_auto_validations_loaded)

    raise "AutoValidations already loaded for #{model_class.name}" if auto_validations_loaded
  end

  def register_loaded_on_model_class!
    model_class.instance_variable_set(:@_active_record_auto_validations_loaded, true)
  end

  def columns
    @columns ||= model_class.columns
  end

  def ignore_column?(column_name)
    return true if column_name == "id" || column_name == "created_at" || column_name == "updated_at"

    ignore_column_names.include?(column_name)
  end

  def ignore_index?(index)
    return true unless index.unique

    index.columns.any? { |index_column_name| ignore_column?(index_column_name) }
  end

  def indexes
    @indexes ||= model_class.connection.indexes(model_class.table_name)
  end

  def insert_active_record_auto_validations_from_columns!
    columns.each do |column|
      next if ignore_column?(column.name)

      auto_validate_boolean_inclusion_on_column!(column) if auto_validate_boolean_inclusion_on_column?(column)
      auto_validate_presence_on_column!(column) if auto_validate_presence_on_column?(column)
      auto_validate_max_length_on_column!(column) if auto_validate_max_length_on_column?(column)
    end
  end

  def insert_active_record_auto_validations_from_indexes!
    indexes.each do |index|
      next if ignore_index?(index)

      # Dont add uniqueness validation to ActsAsList position columns
      if index.columns.include?("position") && model_class.respond_to?(:acts_as_list_top)
        Rails.logger.info do
          "AutoValidate: Skipping unique validation on #{model_class.table_name}##{index.columns.join(",")} because it looks like ActsAsList"
        end

        next
      end

      ActiveRecordAutoValidations::AutoUniqueIndex.execute!(columns: columns, model_class: model_class, index: index)
    end
  end

  def boolean_inclusion_validation_exists_on_column?(column)
    model_class.validators_on(column.name.to_sym).each do |validator|
      return true if validator.kind == :inclusion
    end

    false
  end

  def presence_validation_exists_on_column?(column)
    model_class.validators_on(column.name.to_sym).each do |validator|
      return true if validator.kind == :presence
    end

    false
  end

  def auto_validate_boolean_inclusion_on_column?(column)
    column.type == :boolean &&
      !column.null &&
      !column.name.end_with?("_id") &&
      column.default.nil? &&
      column.default_function.nil? &&
      !boolean_inclusion_validation_exists_on_column?(column)
  end

  def auto_validate_presence_on_column?(column)
    column.type != :boolean &&
      !column.null &&
      !column.name.end_with?("_id") &&
      column.default.nil? &&
      column.default_function.nil? &&
      !presence_validation_exists_on_column?(column)
  end

  def auto_validate_boolean_inclusion_on_column!(column)
    Rails.logger.info { "AutoValidate: Adding boolean inclusion validation to #{model_class.table_name}##{column.name}" }
    model_class.validates column.name.to_sym, inclusion: { in: [true, false] }
  end

  def auto_validate_presence_on_column!(column)
    Rails.logger.info { "AutoValidate: Adding presence validation to #{model_class.table_name}##{column.name}" }
    model_class.validates column.name.to_sym, presence: true
  end

  def auto_validate_max_length_on_column?(column)
    column.type == :string && column.limit && !max_length_validation_exists_on_column?(column)
  end

  def auto_validate_max_length_on_column!(column)
    Rails.logger.info { "AutoValidate: Adding maxlength of #{column.limit} validation to #{model_class.table_name}##{column.name}" }
    model_class.validates column.name.to_sym, allow_blank: true, length: {maximum: column.limit}
  end

  def max_length_validation_exists_on_column?(column)
    model_class.validators_on(column.name.to_sym).each do |validator|
      return true if validator.kind == :length
    end

    false
  end
end
