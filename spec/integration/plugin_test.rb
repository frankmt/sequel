require File.join(File.dirname(__FILE__), 'spec_helper.rb')

# H2 and MSSQL don't support USING joins
unless [:h2, :mssql].include?(INTEGRATION_DB.database_type)
describe "Class Table Inheritance Plugin" do
  before do
    @db = INTEGRATION_DB
    @db.instance_variable_set(:@schemas, {})
    @db.create_table!(:employees) do
      primary_key :id
      String :name
      String :kind
    end
    @db.create_table!(:managers) do
      foreign_key :id, :employees, :primary_key=>true
      Integer :num_staff
    end
    @db.create_table!(:executives) do
      foreign_key :id, :managers, :primary_key=>true
      Integer :num_managers
    end
    @db.create_table!(:staff) do
      foreign_key :id, :employees, :primary_key=>true
      foreign_key :manager_id, :managers
    end
    class ::Employee < Sequel::Model(@db)
      plugin :class_table_inheritance, :key=>:kind, :table_map=>{:Staff=>:staff}
    end 
    class ::Manager < Employee
      one_to_many :staff_members, :class=>:Staff
    end 
    class ::Executive < Manager
    end 
    class ::Staff < Employee
      many_to_one :manager
    end 
    
    @i1 =@db[:employees].insert(:name=>'E', :kind=>'Employee')
    @i2 = @db[:employees].insert(:name=>'S', :kind=>'Staff')
    @i3 = @db[:employees].insert(:name=>'M', :kind=>'Manager')
    @i4 = @db[:employees].insert(:name=>'Ex', :kind=>'Executive')
    @db[:managers].insert(:id=>@i3, :num_staff=>7)
    @db[:managers].insert(:id=>@i4, :num_staff=>5)
    @db[:executives].insert(:id=>@i4, :num_managers=>6)
    @db[:staff].insert(:id=>@i2, :manager_id=>@i4)
    
    clear_sqls
  end
  after do
    @db.drop_table :executives, :managers, :staff, :employees
    [:Executive, :Manager, :Staff, :Employee].each{|s| Object.send(:remove_const, s)}
  end

  specify "should return rows as subclass instances" do
    Employee.order(:id).all.should == [
      Employee.load(:id=>@i1, :name=>'E', :kind=>'Employee'),
      Staff.load(:id=>@i2, :name=>'S', :kind=>'Staff'),
      Manager.load(:id=>@i3, :name=>'M', :kind=>'Manager'),
      Executive.load(:id=>@i4, :name=>'Ex', :kind=>'Executive')
    ]
  end
  
  specify "should lazily load columns in subclass tables" do
    a = Employee.order(:id).all
    a[1][:manager_id].should == nil
    a[1].manager_id.should == @i4
  end
  
  specify "should include schema for columns for tables for ancestor classes" do
    Employee.db_schema.keys.sort_by{|x| x.to_s}.should == [:id, :kind, :name]
    Staff.db_schema.keys.sort_by{|x| x.to_s}.should == [:id, :kind, :manager_id, :name]
    Manager.db_schema.keys.sort_by{|x| x.to_s}.should == [:id, :kind, :name, :num_staff]
    Executive.db_schema.keys.sort_by{|x| x.to_s}.should == [:id, :kind, :name, :num_managers, :num_staff]
  end
  
  specify "should include columns for tables for ancestor classes" do
    Employee.columns.should == [:id, :name, :kind]
    Staff.columns.should == [:id, :name, :kind, :manager_id]
    Manager.columns.should == [:id, :name, :kind, :num_staff]
    Executive.columns.should == [:id, :name, :kind, :num_staff, :num_managers]
  end
  
  specify "should delete rows from all tables" do
    e = Executive.first
    i = e.id
    e.staff_members_dataset.destroy
    e.destroy
    @db[:executives][:id=>i].should == nil
    @db[:managers][:id=>i].should == nil
    @db[:employees][:id=>i].should == nil
  end
  
  # See http://www.sqlite.org/src/tktview/3338b3fa19ac4abee6c475126a2e6d9d61f26ab1
  cspecify "should insert rows into all tables", :sqlite do
    e = Executive.create(:name=>'Ex2', :num_managers=>8, :num_staff=>9)
    i = e.id
    @db[:employees][:id=>i].should == {:id=>i, :name=>'Ex2', :kind=>'Executive'}
    @db[:managers][:id=>i].should == {:id=>i, :num_staff=>9}
    @db[:executives][:id=>i].should == {:id=>i, :num_managers=>8}
  end
  
  specify "should update rows in all tables" do
    Executive.first.update(:name=>'Ex2', :num_managers=>8, :num_staff=>9)
    @db[:employees][:id=>@i4].should == {:id=>@i4, :name=>'Ex2', :kind=>'Executive'}
    @db[:managers][:id=>@i4].should == {:id=>@i4, :num_staff=>9}
    @db[:executives][:id=>@i4].should == {:id=>@i4, :num_managers=>8}
  end
  
  cspecify "should handle many_to_one relationships", :sqlite do
    m = Staff.first.manager
    m.should == Manager[@i4]
    m.should be_a_kind_of(Executive)
  end
  
  cspecify "should handle eagerly loading many_to_one relationships", :sqlite do
    Staff.limit(1).eager(:manager).all.map{|x| x.manager}.should == [Manager[@i4]]
  end
  
  cspecify "should handle eagerly graphing many_to_one relationships", :sqlite do
    ss = Staff.eager_graph(:manager).all
    ss.should == [Staff[@i2]]
    ss.map{|x| x.manager}.should == [Manager[@i4]]
  end
  
  specify "should handle one_to_many relationships" do
    Executive.first.staff_members.should == [Staff[@i2]]
  end
  
  specify "should handle eagerly loading one_to_many relationships" do
    Executive.limit(1).eager(:staff_members).first.staff_members.should == [Staff[@i2]]
  end
  
  cspecify "should handle eagerly graphing one_to_many relationships", :sqlite do
    es = Executive.limit(1).eager_graph(:staff_members).all
    es.should == [Executive[@i4]]
    es.map{|x| x.staff_members}.should == [[Staff[@i2]]]
  end
end
end

describe "Many Through Many Plugin" do
  before do
    @db = INTEGRATION_DB
    @db.instance_variable_set(:@schemas, {})
    @db.create_table!(:albums) do
      primary_key :id
      String :name
    end
    @db.create_table!(:artists) do
      primary_key :id
      String :name
    end
    @db.create_table!(:albums_artists) do
      foreign_key :album_id, :albums
      foreign_key :artist_id, :artists
    end
    class ::Album < Sequel::Model(@db)
      many_to_many :artists
    end 
    class ::Artist < Sequel::Model(@db)
      plugin :many_through_many
    end 
    
    @artist1 = Artist.create(:name=>'1')
    @artist2 = Artist.create(:name=>'2')
    @artist3 = Artist.create(:name=>'3')
    @artist4 = Artist.create(:name=>'4')
    @album1 = Album.create(:name=>'A')
    @album1.add_artist(@artist1)
    @album1.add_artist(@artist2)
    @album2 = Album.create(:name=>'B')
    @album2.add_artist(@artist3)
    @album2.add_artist(@artist4)
    @album3 = Album.create(:name=>'C')
    @album3.add_artist(@artist2)
    @album3.add_artist(@artist3)
    @album4 = Album.create(:name=>'D')
    @album4.add_artist(@artist1)
    @album4.add_artist(@artist4)
    
    clear_sqls
  end
  after do
    @db.drop_table :albums_artists, :albums, :artists
    [:Album, :Artist].each{|s| Object.send(:remove_const, s)}
  end
  
  specify "should handle super simple case with 1 join table" do
    Artist.many_through_many :albums, [[:albums_artists, :artist_id, :album_id]]
    Artist[1].albums.map{|x| x.name}.sort.should == %w'A D'
    Artist[2].albums.map{|x| x.name}.sort.should == %w'A C'
    Artist[3].albums.map{|x| x.name}.sort.should == %w'B C'
    Artist[4].albums.map{|x| x.name}.sort.should == %w'B D'
    
    Artist.filter(:id=>1).eager(:albums).all.map{|x| x.albums.map{|a| a.name}}.flatten.sort.should == %w'A D'
    Artist.filter(:id=>2).eager(:albums).all.map{|x| x.albums.map{|a| a.name}}.flatten.sort.should == %w'A C'
    Artist.filter(:id=>3).eager(:albums).all.map{|x| x.albums.map{|a| a.name}}.flatten.sort.should == %w'B C'
    Artist.filter(:id=>4).eager(:albums).all.map{|x| x.albums.map{|a| a.name}}.flatten.sort.should == %w'B D'
    
    Artist.filter(:artists__id=>1).eager_graph(:albums).all.map{|x| x.albums.map{|a| a.name}}.flatten.sort.should == %w'A D'
    Artist.filter(:artists__id=>2).eager_graph(:albums).all.map{|x| x.albums.map{|a| a.name}}.flatten.sort.should == %w'A C'
    Artist.filter(:artists__id=>3).eager_graph(:albums).all.map{|x| x.albums.map{|a| a.name}}.flatten.sort.should == %w'B C'
    Artist.filter(:artists__id=>4).eager_graph(:albums).all.map{|x| x.albums.map{|a| a.name}}.flatten.sort.should == %w'B D'
  end

  specify "should handle typical case with 3 join tables" do
    Artist.many_through_many :related_artists, [[:albums_artists, :artist_id, :album_id], [:albums, :id, :id], [:albums_artists, :album_id, :artist_id]], :class=>Artist, :distinct=>true
    Artist[1].related_artists.map{|x| x.name}.sort.should == %w'1 2 4'
    Artist[2].related_artists.map{|x| x.name}.sort.should == %w'1 2 3'
    Artist[3].related_artists.map{|x| x.name}.sort.should == %w'2 3 4'
    Artist[4].related_artists.map{|x| x.name}.sort.should == %w'1 3 4'
    
    Artist.filter(:id=>1).eager(:related_artists).all.map{|x| x.related_artists.map{|a| a.name}}.flatten.sort.should == %w'1 2 4'
    Artist.filter(:id=>2).eager(:related_artists).all.map{|x| x.related_artists.map{|a| a.name}}.flatten.sort.should == %w'1 2 3'
    Artist.filter(:id=>3).eager(:related_artists).all.map{|x| x.related_artists.map{|a| a.name}}.flatten.sort.should == %w'2 3 4'
    Artist.filter(:id=>4).eager(:related_artists).all.map{|x| x.related_artists.map{|a| a.name}}.flatten.sort.should == %w'1 3 4'
    
    Artist.filter(:artists__id=>1).eager_graph(:related_artists).all.map{|x| x.related_artists.map{|a| a.name}}.flatten.sort.should == %w'1 2 4'
    Artist.filter(:artists__id=>2).eager_graph(:related_artists).all.map{|x| x.related_artists.map{|a| a.name}}.flatten.sort.should == %w'1 2 3'
    Artist.filter(:artists__id=>3).eager_graph(:related_artists).all.map{|x| x.related_artists.map{|a| a.name}}.flatten.sort.should == %w'2 3 4'
    Artist.filter(:artists__id=>4).eager_graph(:related_artists).all.map{|x| x.related_artists.map{|a| a.name}}.flatten.sort.should == %w'1 3 4'
  end

  specify "should handle extreme case with 5 join tables" do
    Artist.many_through_many :related_albums, [[:albums_artists, :artist_id, :album_id], [:albums, :id, :id], [:albums_artists, :album_id, :artist_id], [:artists, :id, :id], [:albums_artists, :artist_id, :album_id]], :class=>Album, :distinct=>true
    @db[:albums_artists].delete
    @album1.add_artist(@artist1)
    @album1.add_artist(@artist2)
    @album2.add_artist(@artist2)
    @album2.add_artist(@artist3)
    @album3.add_artist(@artist1)
    @album4.add_artist(@artist3)
    @album4.add_artist(@artist4)
    
    Artist[1].related_albums.map{|x| x.name}.sort.should == %w'A B C'
    Artist[2].related_albums.map{|x| x.name}.sort.should == %w'A B C D'
    Artist[3].related_albums.map{|x| x.name}.sort.should == %w'A B D'
    Artist[4].related_albums.map{|x| x.name}.sort.should == %w'B D'
    
    Artist.filter(:id=>1).eager(:related_albums).all.map{|x| x.related_albums.map{|a| a.name}}.flatten.sort.should == %w'A B C'
    Artist.filter(:id=>2).eager(:related_albums).all.map{|x| x.related_albums.map{|a| a.name}}.flatten.sort.should == %w'A B C D'
    Artist.filter(:id=>3).eager(:related_albums).all.map{|x| x.related_albums.map{|a| a.name}}.flatten.sort.should == %w'A B D'
    Artist.filter(:id=>4).eager(:related_albums).all.map{|x| x.related_albums.map{|a| a.name}}.flatten.sort.should == %w'B D'
    
    Artist.filter(:artists__id=>1).eager_graph(:related_albums).all.map{|x| x.related_albums.map{|a| a.name}}.flatten.sort.should == %w'A B C'
    Artist.filter(:artists__id=>2).eager_graph(:related_albums).all.map{|x| x.related_albums.map{|a| a.name}}.flatten.sort.should == %w'A B C D'
    Artist.filter(:artists__id=>3).eager_graph(:related_albums).all.map{|x| x.related_albums.map{|a| a.name}}.flatten.sort.should == %w'A B D'
    Artist.filter(:artists__id=>4).eager_graph(:related_albums).all.map{|x| x.related_albums.map{|a| a.name}}.flatten.sort.should == %w'B D'
  end
end