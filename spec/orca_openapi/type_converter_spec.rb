# frozen_string_literal: true

require 'spec_helper'

# Named test classes must be defined outside examples because:
# - T::Struct subclasses cannot be created with Class.new
# - T::Enum constants must be assigned to real constants
module TypeConverterTestFixtures
  class SimpleSchema < T::Struct
    const :id, String
  end

  class ItemSchema < T::Struct
    const :name, String
  end

  class OptionalSchema < T::Struct
    const :value, String
  end

  class PlainStruct < T::Struct
    const :name, String
  end

  class Status < T::Enum
    enums do
      Active = new('active')
      Inactive = new('inactive')
      Pending = new('pending')
    end
  end
end

RSpec.describe OrcaOpenAPI::TypeConverter do
  describe '.convert' do
    context 'with primitive types' do
      it 'converts String' do
        expect(described_class.convert(String)).to eq(type: 'string')
      end

      it 'converts Integer with int64 format' do
        expect(described_class.convert(Integer)).to eq(type: 'integer', format: 'int64')
      end

      it 'converts Float' do
        expect(described_class.convert(Float)).to eq(type: 'number', format: 'float')
      end

      it 'converts Numeric' do
        expect(described_class.convert(Numeric)).to eq(type: 'number')
      end

      it 'converts TrueClass as boolean' do
        expect(described_class.convert(TrueClass)).to eq(type: 'boolean')
      end

      it 'converts FalseClass as boolean' do
        expect(described_class.convert(FalseClass)).to eq(type: 'boolean')
      end

      it 'converts NilClass as null' do
        expect(described_class.convert(NilClass)).to eq(type: 'null')
      end

      it 'converts Date' do
        expect(described_class.convert(Date)).to eq(type: 'string', format: 'date')
      end

      it 'converts Time' do
        expect(described_class.convert(Time)).to eq(type: 'string', format: 'date-time')
      end

      it 'converts DateTime' do
        expect(described_class.convert(DateTime)).to eq(type: 'string', format: 'date-time')
      end

      it 'converts Symbol as string' do
        expect(described_class.convert(Symbol)).to eq(type: 'string')
      end
    end

    context 'with Sorbet T::Types::Simple wrappers' do
      it 'unwraps Simple(String)' do
        expect(described_class.convert(T::Utils.coerce(String))).to eq(type: 'string')
      end

      it 'unwraps Simple(Integer)' do
        expect(described_class.convert(T::Utils.coerce(Integer))).to eq(type: 'integer', format: 'int64')
      end
    end

    context 'with T::Boolean' do
      it 'converts to boolean' do
        result = described_class.convert(T::Utils.coerce(T::Boolean))
        # T::Boolean is T.any(TrueClass, FalseClass) — could be oneOf or collapsed
        expect(result).to satisfy('be boolean or oneOf booleans') { |r|
          [{ type: 'boolean' }, { oneOf: [{ type: 'boolean' }, { type: 'boolean' }] }].include?(r)
        }
      end
    end

    context 'with nilable types' do
      it 'converts T.nilable(String) to type array with null (OAS 3.1)' do
        type = T::Utils.coerce(T.nilable(String))
        result = described_class.convert(type)

        expect(result[:type]).to eq(%w[string null])
      end

      it 'converts T.nilable(Integer) to type array with null and int64 format' do
        type = T::Utils.coerce(T.nilable(Integer))
        result = described_class.convert(type)

        expect(result[:type]).to eq(%w[integer null])
        expect(result[:format]).to eq('int64')
      end

      it 'converts T.nilable(Float) preserving format' do
        type = T::Utils.coerce(T.nilable(Float))
        result = described_class.convert(type)

        expect(result[:type]).to eq(%w[number null])
        expect(result[:format]).to eq('float')
      end
    end

    context 'with array types' do
      it 'converts T::Array[String]' do
        type = T::Utils.coerce(T::Array[String])
        result = described_class.convert(type)

        expect(result).to eq(type: 'array', items: { type: 'string' })
      end

      it 'converts T::Array[Integer]' do
        type = T::Utils.coerce(T::Array[Integer])
        result = described_class.convert(type)

        expect(result).to eq(type: 'array', items: { type: 'integer', format: 'int64' })
      end

      it 'converts nested arrays T::Array[T::Array[String]]' do
        type = T::Utils.coerce(T::Array[T::Array[String]])
        result = described_class.convert(type)

        expect(result).to eq(
          type: 'array',
          items: { type: 'array', items: { type: 'string' } }
        )
      end
    end

    context 'with hash types' do
      it 'converts T::Hash[String, Integer]' do
        type = T::Utils.coerce(T::Hash[String, Integer])
        result = described_class.convert(type)

        expect(result).to eq(
          type: 'object',
          additionalProperties: { type: 'integer', format: 'int64' }
        )
      end
    end

    context 'with union types (non-nilable)' do
      it 'converts T.any(String, Integer) to oneOf' do
        type = T::Utils.coerce(T.any(String, Integer))
        result = described_class.convert(type)

        expect(result[:oneOf]).to contain_exactly(
          { type: 'string' },
          { type: 'integer', format: 'int64' }
        )
      end
    end

    context 'with enum types' do
      it 'converts T::Enum subclass to string with enum values' do
        result = described_class.convert(TypeConverterTestFixtures::Status)

        expect(result[:type]).to eq('string')
        expect(result[:enum]).to contain_exactly('active', 'inactive', 'pending')
      end
    end

    context 'with T::Struct classes' do
      it 'returns a $ref to the schema component' do
        result = described_class.convert(TypeConverterTestFixtures::SimpleSchema)

        expect(result).to eq(
          '$ref' => '#/components/schemas/type_converter_test_fixtures_simple_schema'
        )
      end
    end

    context 'with plain T::Struct classes' do
      it 'returns a $ref to the schema component' do
        result = described_class.convert(TypeConverterTestFixtures::PlainStruct)

        expect(result).to eq(
          '$ref' => '#/components/schemas/type_converter_test_fixtures_plain_struct'
        )
      end
    end

    context 'with arrays of schema classes' do
      it 'returns array with $ref items' do
        type = T::Utils.coerce(T::Array[TypeConverterTestFixtures::ItemSchema])
        result = described_class.convert(type)

        expect(result).to eq(
          type: 'array',
          items: { '$ref' => '#/components/schemas/type_converter_test_fixtures_item_schema' }
        )
      end
    end

    context 'with nilable schema classes' do
      it 'wraps $ref in oneOf with null' do
        type = T::Utils.coerce(T.nilable(TypeConverterTestFixtures::OptionalSchema))
        result = described_class.convert(type)

        expect(result).to eq(
          oneOf: [
            { '$ref' => '#/components/schemas/type_converter_test_fixtures_optional_schema' },
            { type: 'null' }
          ]
        )
      end
    end

    context 'with unknown types' do
      it 'falls back to object for unrecognized classes' do
        stub_const('CustomClass', Class.new)
        expect(described_class.convert(CustomClass)).to eq(type: 'object')
      end
    end
  end
end
