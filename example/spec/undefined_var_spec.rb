# This is intentionally busted
describe "undefined variable error" do
  it "should error" do
    expect(undefined_variable).to be(true)
  end
end
