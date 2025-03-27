import os
from mcp.server.fastmcp import FastMCP

mcp = FastMCP()


@mcp.tool()
def get_files():
    """返回当前目录文件列表"""
    return os.listdir(".")


if __name__ == "__main__":
    mcp.run(transport='sse')
