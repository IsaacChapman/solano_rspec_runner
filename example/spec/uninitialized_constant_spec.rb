# This is intentionally busted
describe "uninitialized constant error" do
  it "should error" do
    expect(NonExistingClass.true).to be(true)
  end
end
