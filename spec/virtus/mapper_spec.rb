require 'virtus'
require 'virtus/mapper'

module Virtus
  RSpec.describe Mapper do

    before do
      module Examples
        class PersonMapper
          include Virtus.model
          include Virtus::Mapper

          attribute :id, Integer, from: :person_id, strict: true, required: true
          attribute :first_name, String
          attribute :last_name, String, from: :surname
          attribute :address,
                    String,
                    default: '',
                    from: lambda { |atts| atts[:address][:street] rescue '' }
        end

        module EmploymentMapper
          include Virtus.module
          include Virtus::Mapper

          attribute :company, String, from: :business
          attribute :job_title, String, from: :position
          attribute :salary, Integer
          attribute :fulltime, Virtus::Attribute::Boolean
        end

        module TraitsMapper
          include Virtus.module
          include Virtus::Mapper

          attribute :eye_color, String, from: :eyecolor
        end

        class DogMapper
          include Virtus.model
          include Virtus::Mapper

          attribute :name, String, from: :shelter, default: 'Spot'
        end
      end
    end

    let(:person_id) { 1 }
    let(:first_name) { 'John' }
    let(:last_name) { 'Doe' }
    let(:address) { '1122 Something Avenue' }
    let(:person_attrs) {
      { person_id: person_id,
        first_name: first_name,
        surname: last_name,
        address: { 'street' => address } }
    }
    let(:employment_attrs) {
      { salary: 100,
        business: 'RentPath',
        position: 'Programmer',
        fulltime: '1' }
    }
    let(:person) { Examples::PersonMapper.new(person_attrs) }

    describe '#attr_set' do
      it 'initializes to non-nil value' do
        expect(person.attr_set).not_to be_nil
      end

      it 'contains expected attributes' do
        attr_set_names = person.attr_set.collect(&:name)
        [:id, :first_name, :last_name, :address].each do |name|
          expect(attr_set_names).to include(name)
        end
      end

      it "is not the same as Virtus's class-scope attribute_set" do
        expect(person.attr_set).not_to equal(person.class.attribute_set)
      end
    end

    describe 'attribute with from option as symbol' do
      it 'translates key' do
        expect(person.last_name).to eq(last_name)
      end

      it 'does not create method from original key' do
        expect { person.surname }.to raise_error(NoMethodError)
      end

      describe 'required attribute with name key, missing from key' do
        it 'raises error' do
          expect { Examples::PersonMapper.new({id: 1}) }.to raise_error
        end
      end

      describe 'attribute with name key, missing from key' do
        it 'returns nil from reader method' do
          data = { person_id: 1, last_name: 'Smith' }
          person = Examples::PersonMapper.new(data)
          expect(person.last_name).to be_nil
        end
      end

      describe 'when name and from keys exist in initialized attributes' do
        it 'prefers from data to name data' do
          data = person_attrs.merge({ last_name: 'Smith' })
          person = Examples::PersonMapper.new(data)
          expect(person.last_name).to eq('Doe')
        end
      end
    end

    describe 'attribute with from option as callable object' do
      it 'calls the object and passes the attributes hash' do
        callable = Examples::PersonMapper.attribute_set[:address].options[:from]
        expect(callable).to receive(:call) { person_attrs }
        Examples::PersonMapper.new(person_attrs)
      end

      it 'sets attribute value to result of call' do
        expect(person.address).to eq(address)
      end
    end

    describe 'attribute without from option' do
      it 'behaves as usual' do
        expect(person.first_name).to eq(first_name)
      end
    end

    it 'maps attributes with indifferent access' do
      person = Examples::PersonMapper.new({ person_id: 1,
                                      first_name: first_name,
                                      'surname' => last_name })
      expect(person.last_name).to eq('Doe')
    end

    describe 'given no arguments to constructor' do
      it 'does not raise error' do
        expect { Examples::DogMapper.new }.not_to raise_error
      end

      it 'respects defaults' do
        expect(Examples::DogMapper.new.name).to eq('Spot')
      end
    end

    describe 'given nil values' do
      it 'respects nil values' do
        expect(Examples::DogMapper.new(name: nil).name).to be_nil
      end
    end

    describe '#raw_attributes' do
      let(:person) { Examples::PersonMapper.new(person_attrs.merge({ unused: true })) }

      it 'preserves unused attributes' do
        expect(person.raw_attributes[:unused]).to be true
      end

      describe 'keys that do not have corresponding attributes' do
        it 'do not get instance methods' do
          expect { person.unused }.to raise_error(NoMethodError)
        end
      end
    end

    describe '#add_attributes' do
      let(:data) {
        { person_id: person_id,
          first_name: first_name,
          surname: last_name,
          address: { 'street' => address },
          salary: 100,
          business: 'RentPath',
          position: 'Programmer',
          fulltime: '1' }
      }
      let(:person1) { Examples::PersonMapper.new(data) }
      let(:person2) { Examples::PersonMapper.new(data) }
      let(:mod) { Examples::EmploymentMapper }


      it 'does not affect class-scope attribute_set' do
        expect { person2.add_attributes(mod) }.not_to change {
          person2.class.attribute_set.to_a }
      end

      it 'adds module attributes to #attr_set' do
        module_attributes = Class.new do
          include Examples::EmploymentMapper
        end.attribute_set.to_a
        person2.add_attributes(mod)
        attr_names = person2.attr_set.collect(&:name)
        module_attributes.each do |att|
          expect(attr_names).to include(att.name)
        end
      end

      describe 'for single module' do
        let(:person) {
          Examples::PersonMapper.new(person_attrs.merge(employment_attrs))
        }

        before do
          person.add_attributes(Examples::EmploymentMapper)
        end

        it 'coerces data' do
          expect(person.fulltime).to be true
        end

        it 'updates unmapped attribute values' do
          expect(person.salary).to eq(100)
        end

        it 'updates mapped attribute values' do
          expect(person.job_title).to eq('Programmer')
        end

        it 'adds module attributes to attr_set' do
          attr_names = person.attr_set.collect(&:name)
          [:id,
           :first_name,
           :last_name,
           :address,
           :company,
           :job_title,
           :salary].each do |attr_name|
             expect(attr_names).to include(attr_name)
           end
        end
      end

      describe 'for multiple modules' do
        let(:person) {
          Examples::PersonMapper.new(
            person_attrs.merge(employment_attrs.merge({ eyecolor: 'green' }))
          )
        }

        before do
          person.add_attributes(Examples::EmploymentMapper)
          person.add_attributes(Examples::TraitsMapper)
        end

        it 'updates mapped attributes for last module' do
          expect(person.eye_color).to eq('green')
        end

        it 'updates mapped attributes for first module' do
          expect(person.salary).to eq(100)
          expect(person.company).to eq('RentPath')
          expect(person.job_title).to eq('Programmer')
        end

        it 'adds module attributes to attr_set' do
          attr_names = person.attr_set.collect(&:name)
          [:id,
           :first_name,
           :last_name,
           :address,
           :company,
           :job_title,
           :salary,
           :eye_color].each do |attr_name|
             expect(attr_names).to include(attr_name)
           end
        end
      end
    end
  end
end
