namespace WowPacketParser.Misc
{
    public interface IAttribute
    {
        bool IsPrimaryKey { get { return false; } set { } }
        bool IsVisible() => false;
    }
}
