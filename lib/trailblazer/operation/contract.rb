Reform::Form.class_eval do # THIS IS OF COURSE PROTOTYPING!
  def call(params, &block)
    bool = validate(params, &block)
    Result.new(self)
  end

  class Result < SimpleDelegator
    def success?
      errors.empty?
    end
  end
end
# Best practices for using contract.
#
# * inject contract instance via constructor to #contract
# * allow contract setup and memo via #contract(model, options)
# * allow implicit automatic setup via #contract and class.contract_class
#
# Needs Operation#model.
# Needs #[], #[]= skill dependency.
class Trailblazer::Operation
  module Contract
    module DSL
      # This is the class level DSL method.
      #   Op.contract #=> returns contract class
      #   Op.contract do .. end # defines contract
      #   Op.contract CommentForm # copies (and subclasses) external contract.
      #   Op.contract CommentForm do .. end # copies and extends contract.
      def contract(name=:default, constant=nil, &block)
        heritage.record(:contract, name, constant, &block)

        path, form_class = Trailblazer::DSL::Build.new.({ prefix: :contract, class: Reform::Form, container: self }, name, constant, block)

        self[path] = form_class
      end
    end

    Build = ->(operation, options) { operation["contract"] = operation.contract_for }

    #- import!
    # def self.[](contract_class=self["contract.default.class"])
    def self.[](contract_class)
      {
         include: [ContractFor],
            step: Build, # calls contract_for ATM.
            name: "contract.build",
          skills: { },
        operator: :>,
      }
    end


    module ContractFor # FIXME: rename!
      # Instantiate the contract, either by using the user's contract passed into #validate
      # or infer the Operation contract.
      def contract_for(model:self["model"], options:{}, contract_class:self["contract.default.class"])
        contract!(model: model, options: options, contract_class: contract_class)
      end

      # Override to construct your own contract.
      def contract!(model:nil, options:{}, contract_class:nil)
        contract_class.new(model, options)
      end
    end

    # result.contract = {..}
    # result.contract.errors = {..}
    # Deviate to left track if optional key is not found in params.
    # Deviate to left if validation result falsey.
    module Validate
      def self.[](key:nil)
        [
          key ? {
            step: ->(input, options) { options["params"] = options["params"][key] }, # FIXME: we probably shouldn't overwrite params?
            operator: :&,
            skills: {},
            name: "validate.params.extract",
            } : nil,
          {
            include: [self],
            step: ->(input, options) { input.validate(options["params"]) }, # FIXME: how could we deal here with polymorphic keys?
            operator: :&,
            skills: { },
            name: "contract.validate",
          }
        ].compact
      end

      def validate(params, contract:self["contract"], path:"contract") # :params
        # DISCUSS: should we only have path here and then look up contract ourselves?
        result = validate_contract(contract, params) # run validation.  # FIXME: must be overridable.

        self["result.#{path}"] = result

        if valid = result.success? # FIXME: to_bool or success?
          yield result if block_given?
        else
          # self["errors.#{path}"] = result.errors # TODO: remove me
        end

        valid
      end

      def validate_contract(contract, params)
        contract.(params)
      end
    end
  end # Contract
end
