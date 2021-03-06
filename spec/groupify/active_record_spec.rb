require 'active_record'

puts "ActiveRecord version #{ActiveSupport::VERSION::STRING}"

# Load database config
if JRUBY
  require 'jdbc/sqlite3'
  require 'active_record'
  require 'active_record/connection_adapters/jdbcsqlite3_adapter'
else
  require 'sqlite3'
end

RSpec.configure do |config|
  config.before(:suite) do
    DatabaseCleaner[:active_record].strategy = :transaction
  end

  config.before(:each) do
    DatabaseCleaner[:active_record].start
  end

  config.after(:each) do
    DatabaseCleaner[:active_record].clean
  end
end

ActiveRecord::Base.establish_connection( :adapter => 'sqlite3', :database => ":memory:" )

ActiveRecord::Migration.verbose = false
ActiveRecord::Schema.define(:version => 1) do

  create_table :groups do |t|
    t.string     :name
    t.string     :type
  end
  
  create_table :group_memberships do |t|
    t.string     :member_type
    t.integer    :member_id
    t.integer    :group_id
    t.string     :group_name
    t.string     :membership_type
  end

  create_table :users do |t|
    t.string   :name
    t.string   :type
  end

  create_table :widgets do |t|
    t.string     :name
  end

  create_table :projects do |t|
    t.string     :name
  end

  create_table :organizations do |t|
    t.string     :name
  end
end

require 'groupify/adapter/active_record'

class User < ActiveRecord::Base  
  acts_as_group_member
  acts_as_named_group_member
end

class Manager < User
end

class Widget < ActiveRecord::Base
  acts_as_group_member
end

class Project < ActiveRecord::Base
  acts_as_named_group_member
end

class Group < ActiveRecord::Base  
  acts_as_group :members => [:users, :widgets], :default_members => :users
end

class Organization < Group
  has_members :managers
end

class GroupMembership < ActiveRecord::Base  
  acts_as_group_membership
end

describe Group do
  it { should respond_to :members}
  it { should respond_to :add }
end

describe User do
  it { should respond_to :groups}
  it { should respond_to :in_group?}
  it { should respond_to :in_any_group?}
  it { should respond_to :in_all_groups?}
  it { should respond_to :shares_any_group?}
end

if DEBUG
  ActiveRecord::Base.logger = Logger.new(STDOUT)
end

describe Groupify::ActiveRecord do
  let!(:user) { User.create! }
  let!(:group) { Group.create! }
  let(:widget) { Widget.create! }

  context 'when using groups' do
    it "members and groups are empty when initialized" do
      expect(user.groups).to be_empty
      expect(User.new.groups).to be_empty

      expect(Group.new.members).to be_empty
      expect(group.members).to be_empty
    end
    
    it "adds a group to a member" do
      user.groups << group
      expect(user.groups).to include(group)
      expect(group.members).to include(user)
      expect(group.users).to include(user)
    end
    
    it "adds a member to a group" do
      expect(user.groups).to be_empty
      group.add user
      expect(user.groups).to include(group)
      expect(group.members).to include(user)
    end

    it "adds multiple members to a group" do
      group.add(user, widget)
      expect(group.users).to include(user)
      expect(group.widgets).to include(widget)

      users = [User.create!, User.create!]
      group.add(users)
      expect(group.users).to include(*users)
    end

    it 'lists which member classes can belong to this group' do
      expect(group.class.member_classes).to include(User, Widget)
      expect(group.member_classes).to include(User, Widget)
      
      expect(Organization.member_classes).to include(User, Widget, Manager)
    end
    
    it "finds members by group" do
      group.add user
      
      expect(User.in_group(group).first).to eql(user)
    end

    it "finds the group a member belongs to" do
      group.add user
      
      expect(Group.with_member(user).first).to eq(group)
    end

    context 'when removing' do
      it "removes members from a group" do
        group.add user
        group.add widget

        group.users.delete(user)
        group.widgets.destroy(widget)

        expect(group.widgets).to_not include(widget)
        expect(group.users).to_not include(user)

        expect(widget.groups).to_not include(group)
        expect(user.groups).to_not include(group)
      end

      it "removes groups from a member" do
        group.add widget
        group.add user

        user.groups.delete(group)
        widget.groups.destroy(group)

        expect(group.widgets).to_not include(widget)
        expect(group.users).to_not include(user)

        expect(widget.groups).to_not include(group)
        expect(user.groups).to_not include(group)
      end

      it "removes the membership relation when a member is destroyed" do
        group.add user
        user.destroy
        expect(group).not_to be_destroyed
        expect(group.users).not_to include(user)
      end

      it "removes the membership relations when a group is destroyed" do
        group.add user
        group.add widget
        group.destroy

        expect(user).not_to be_destroyed
        expect(user.reload.groups).to be_empty

        expect(widget).not_to be_destroyed
        expect(widget.reload.groups).to be_empty
      end
    end

    context 'when checking group membership' do
      it "members can check if they belong to any/all groups" do
        user.groups << group
        group2 = Group.create!
        user.groups << group2
        group3 = Group.create!
        
        expect(user.groups).to include(group)
        expect(user.groups).to include(group2)
        
        expect(User.in_group(group).first).to eql(user)
        expect(User.in_group(group2).first).to eql(user)
        expect(user.in_group?(group)).to be true
        
        expect(User.in_any_group(group).first).to eql(user)
        expect(User.in_any_group(group3)).to be_empty
        expect(user.in_any_group?(group2, group3)).to be true
        expect(user.in_any_group?(group3)).to be false

        expect(User.in_all_groups(group, group2).first).to eql(user)
        expect(User.in_all_groups([group, group2]).first).to eql(user)
        expect(user.in_all_groups?(group, group2)).to be true
        expect(user.in_all_groups?(group, group3)).to be false
      end

      it "members can check if groups are shared" do
        user.groups << group
        widget.groups << group
        user2 = User.create!(:groups => [group])
        
        expect(user.shares_any_group?(widget)).to be true
        expect(Widget.shares_any_group(user).to_a).to include(widget)
        expect(User.shares_any_group(widget).to_a).to include(user, user2)

        expect(user.shares_any_group?(user2)).to be true
        expect(User.shares_any_group(user).to_a).to include(user2)
      end
    end

    context 'when merging groups' do
      let(:task) { Task.create! }
      let(:manager) { Manager.create! }

      it "moves the members from source to destination and destroys the source" do
        source = Group.create!
        destination = Organization.create!

        source.add(user)
        destination.add(manager)

        destination.merge!(source)
        expect(source.destroyed?).to be true
        
        expect(destination.users).to include(user, manager)
        expect(destination.managers).to include(manager)
      end

      it "fails to merge if the destination group cannot contain the source group's members" do
        source = Organization.create!
        destination = Group.create!

        source.add(manager)
        destination.add(user)

        # Managers cannot be members of a Group
        expect {destination.merge!(source)}.to raise_error(ArgumentError)
      end

      it "merges incompatible groups as long as all the source members can be moved to the destination" do
        source = Organization.create!
        destination = Group.create!

        source.add(user)
        destination.add(widget)

        expect {destination.merge!(source)}.to_not raise_error

        expect(source.destroyed?).to be true
        expect(destination.users.to_a).to include(user)
        expect(destination.widgets.to_a).to include(widget)
      end
    end

    context "when using membership types with groups" do
      it 'adds groups to a member with a specific membership type' do
        user.group_memberships.create!(group: group, as: :admin)
        
        expect(user.groups).to include(group)
        expect(group.members).to include(user)
        expect(group.users).to include(user)

        expect(user.groups(:as => :admin)).to include(group)
        expect(user.groups.as(:admin)).to include(group)
        expect(group.members).to include(user)
        expect(group.users).to include(user)
      end

      it 'adds members to a group with specific membership types' do
        group.add(user, as: 'manager')
        group.add(widget)

        expect(user.groups).to include(group)
        expect(group.members).to include(user)
        expect(group.members.as(:manager)).to include(user)
        expect(group.users).to include(user)

        expect(user.groups(:as => :manager)).to include(group)
        expect(group.members).to include(user)
        expect(group.users).to include(user)
      end

      it "adds multiple members to a group with a specific membership type" do
        manager = User.create!
        group.add(user, manager, as: :manager)

        expect(group.users.as(:manager)).to include(user, manager)
        expect(group.users(as: :manager)).to include(user, manager)
      end

      it "finds members by membership type" do
        group.add user, as: 'manager'
        expect(User.as(:manager)).to include(user)
      end

      it "finds members by group with membership type" do
        group.add user, as: 'employee'

        expect(User.in_group(group).as('employee').first).to eql(user)
      end

      it "finds the group a member belongs to with a membership type" do
        group.add user, as: Manager
        user.groups.create!
        
        expect(Group.with_member(user).as(Manager)).to eq([group])
      end

      it "checks if members belong to any groups with a certain membership type" do
        group2 = Group.create!
        user.group_memberships.create!([{group: group, as: 'employee'}, {group: group2}])

        expect(User.in_any_group(group, group2).as('employee').first).to eql(user)
      end

      it "checks if members belong to all groups with a certain membership type" do
        group2 = Group.create!
        group3 = Group.create!
        user.group_memberships.create!([{group: group, as: 'employee'}, {group: group2, as: 'employee'}, {group: group3, as: 'contractor'}])
        
        expect(User.in_all_groups(group, group2).as('employee').first).to eql(user)
        expect(User.in_all_groups([group, group2]).as('employee').first).to eql(user)
        expect(User.in_all_groups(group, group3).as('employee')).to be_empty

        expect(user.in_all_groups?(group, group2, group3)).to be true
        expect(user.in_all_groups?(group, group2, as: :employee)).to be true
        expect(user.in_all_groups?(group, group3, as: 'employee')).to be false
      end

      it "checks if members belong to only groups with a certain membership type" do
        group2 = Group.create!
        group3 = Group.create!
        group4 = Group.create!
        user.group_memberships.create!([{group: group, as: 'employee'}, {group: group2, as: 'employee'}, {group: group3, as: 'contractor'}, {group: group4, as: 'employee'}])

        expect(User.in_only_groups(group, group2, group4).as('employee').first).to eql(user)
        expect(User.in_only_groups([group, group2]).as('employee')).to be_empty
        expect(User.in_only_groups(group, group2, group3, group4).as('employee')).to be_empty

        expect(user.in_only_groups?(group, group2, group3, group4))
        expect(user.in_only_groups?(group, group2, group4, as: 'employee')).to be true
        expect(user.in_only_groups?(group, group2, as: 'employee')).to be false
        expect(user.in_only_groups?(group, group2, group3, group4, as: 'employee')).to be false
      end

      it "members can check if groups are shared with the same membership type" do
        user2 = User.create!
        group.add(user, user2, widget, as: "Sub Group #1")
        
        expect(user.shares_any_group?(widget, as: "Sub Group #1")).to be true
        expect(Widget.shares_any_group(user).as("Sub Group #1").to_a).to include(widget)
        expect(User.shares_any_group(widget).as("Sub Group #1").to_a).to include(user, user2)

        expect(user.shares_any_group?(user2, as: "Sub Group #1")).to be true
        expect(User.shares_any_group(user).as("Sub Group #1").to_a).to include(user2)
      end

      context "when removing" do
        before(:each) do
          group.add user, as: 'employee'
          group.add user, as: 'manager'
        end

        it "removes all membership types when removing a member from a group" do
          group.add user

          group.users.destroy(user)

          expect(user.groups).to_not include(group)
          expect(user.groups.as('manager')).to_not include(group)
          expect(user.groups.as('employee')).to_not include(group)
          expect(group.users).to_not include(user)
        end

        it "removes a specific membership type from the member side" do
          user.groups.destroy(group, as: 'manager')
          expect(user.groups.as('manager')).to be_empty
          expect(user.groups.as('employee')).to include(group)
          expect(user.groups).to include(group)
        end

        it "removes a specific membership type from the group side" do
          group.users.delete(user, as: :manager)
          expect(user.groups.as('manager')).to be_empty
          expect(user.groups.as('employee')).to include(group)
          expect(user.groups).to include(group)
        end

        it "retains the member in the group if all membership types have been removed" do
          group.users.destroy(user, as: 'manager')
          user.groups.delete(group, as: 'employee')
          expect(user.groups).to include(group)
        end
      end
    end
  end
  
  context 'when using named groups' do
    before(:each) do
      user.named_groups.concat :admin, :user, :poster
    end

    it "enforces uniqueness" do
      user.named_groups << :admin
      expect(user.named_groups.count{|g| g == :admin}).to eq(1)
    end

    it "queries named groups" do
      expect(user.named_groups).to include(:user, :admin)
    end

    it "removes named groups" do
      user.named_groups.delete(:admin, :poster)
      expect(user.named_groups).to include(:user)
      expect(user.named_groups).to_not include(:admin, :poster)

      user.named_groups.destroy(:user)
      expect(user.named_groups).to be_empty
    end

    it "removes all named groups" do
      user.named_groups.destroy_all
      expect(user.named_groups).to be_empty
    end
     
    it "checks if a member belongs to one named group" do
      expect(user.in_named_group?(:admin)).to be true
      expect(User.in_named_group(:admin).first).to eql(user)
    end

    it "checks if a member belongs to any named group" do
      expect(user.in_any_named_group?(:admin, :user, :test)).to be true
      expect(user.in_any_named_group?(:foo, :bar)).to be false

      expect(User.in_any_named_group(:admin, :test).first).to eql(user)
      expect(User.in_any_named_group(:test)).to be_empty
    end

    it "checks if a member belongs to all named groups" do
      expect(user.in_all_named_groups?(:admin, :user)).to be true
      expect(user.in_all_named_groups?(:admin, :user, :test)).to be false
      expect(User.in_all_named_groups(:admin, :user).first).to eql(user)
    end

    it "checks if a member belongs to only certain named groups" do
      expect(user.in_only_named_groups?(:admin, :user, :poster)).to be true
      expect(user.in_only_named_groups?(:admin, :user, :poster, :foo)).to be false
      expect(user.in_only_named_groups?(:admin, :user)).to be false
      expect(user.in_only_named_groups?(:admin, :user, :test)).to be false

      expect(User.in_only_named_groups(:admin, :user, :poster).first).to eql(user)
      expect(User.in_only_named_groups(:admin, :user, :poster, :foo)).to be_empty
      expect(User.in_only_named_groups(:admin)).to be_empty
    end

    it "checks if named groups are shared" do
      user2 = User.create!(:named_groups => [:admin])
      
      expect(user.shares_any_named_group?(user2)).to be true
      expect(User.shares_any_named_group(user).to_a).to include(user2)
    end

    context 'and using membership types with named groups' do
      before(:each) do
        user.named_groups.concat :team1, :team2, as: 'employee'
        user.named_groups.push :team3, as: 'manager'
        user.named_groups.push :team1, as: 'developer'
      end

      it "queries named groups, filtering by membership type" do
        expect(user.named_groups).to include(:team1, :team2, :team3)
        expect(user.named_groups.as('manager')).to eq([:team3])
      end

      it "enforces uniqueness of named groups" do
        user.named_groups << :team1
        expect(user.named_groups.count{|g| g == :team1}).to eq(1)
        expect(user.group_memberships.where(group_name: :team1, membership_type: nil).count).to eq(1)
        expect(user.group_memberships.where(group_name: :team1, membership_type: 'employee').count).to eq(1)
        expect(user.named_groups.as('employee').count{|g| g == :team1}).to eq(1)
      end

      it "enforces uniqueness of group name and membership type for group memberships" do
        user.named_groups.push :team1, as: 'employee'
        expect(user.group_memberships.where(group_name: :team1, membership_type: nil).count).to eq(1)
        expect(user.group_memberships.where(group_name: :team1, membership_type: 'employee').count).to eq(1)
        expect(user.named_groups.count{|g| g == :team1}).to eq(1)
        expect(user.named_groups.as('employee').count{|g| g == :team1}).to eq(1)
      end

      it "checks if a member belongs to one named group with a certain membership type" do
        expect(user.in_named_group?(:team1, as: 'employee')).to be true
        expect(User.in_named_group(:team1).as('employee').first).to eql(user)
      end

      it "checks if a member belongs to any named group with a certain membership type" do
        expect(user.in_any_named_group?(:team1, :team3, as: 'employee')).to be true
        expect(User.in_any_named_group(:team2, :team3).as('manager').first).to eql(user)
      end

      it "checks if a member belongs to all named groups with a certain membership type" do
        expect(user.in_all_named_groups?(:team1, :team2, as: 'employee')).to be true
        expect(user.in_all_named_groups?(:team1, :team3, as: 'employee')).to be false
        expect(User.in_all_named_groups(:team1, :team2).as('employee').first).to eql(user)
      end

      it "checks if a member belongs to only certain named groups with a certain membership type" do
        expect(user.in_only_named_groups?(:team1, :team2, as: 'employee')).to be true
        expect(user.in_only_named_groups?(:team1, as: 'employee')).to be false
        expect(user.in_only_named_groups?(:team1, :team3, as: 'employee')).to be false
        expect(user.in_only_named_groups?(:foo, as: 'employee')).to be false

        expect(User.in_only_named_groups(:team1, :team2).as('employee').first).to eql(user)
        expect(User.in_only_named_groups(:team1).as('employee')).to be_empty
        expect(User.in_only_named_groups(:foo).as('employee')).to be_empty
      end

      it "checks if a member shares any named groups with a certain membership type" do
        project = Project.create!(:named_groups => [:team3])

        expect(user.shares_any_named_group?(project, as: 'manager')).to be true
        expect(User.shares_any_named_group(project).as('manager').to_a).to include(user)
      end

      it "removes named groups with a certain membership type" do
        user.named_groups.delete(:team1, as: :employee)
        expect(user.named_groups.as(:employee)).to include(:team2)
        expect(user.named_groups.as(:employee)).to_not include(:team1)
        expect(user.named_groups.as(:developer)).to include(:team1)
        expect(user.named_groups).to include(:team1)
      end

      it "removes all named group memberships if membership type is not specified" do
        user.named_groups.destroy(:team1)
        expect(user.named_groups).to_not include(:team1)
        expect(user.named_groups.as(:employee)).to_not include(:team1)
        expect(user.named_groups.as(:developer)).to_not include(:team1)
        expect(user.named_groups.as(:employee)).to include(:team2)
      end
    end
  end

   
end
