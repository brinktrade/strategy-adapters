// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.10;
pragma abicoder v1;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol';
import '../token/IWETH.sol';

contract NftAdapter is ERC721Holder {
  IWETH public weth;
  bool public initialized;

  /// @dev Adapter Owner
  address payable private constant ADAPTER_OWNER = payable(0x71795b2d53Ffbe5b1805FE725538E4f8fBD29e26);

  /// @dev Ethereum address representations
  IERC20 private constant _ETH_ADDRESS = IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
  IERC20 private constant _ZERO_ADDRESS = IERC20(0x0000000000000000000000000000000000000000);

  /// @dev Max uint
  uint256 private constant MAX_INT = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

  /// @dev initialize the contract with WETH address
  /// @param _weth Address of weth
  function initialize (IWETH _weth) external {
    require(!initialized, 'INITIALIZED');
    initialized = true;
    weth = _weth;
  }

  function sellForToken(address to, bytes memory data, IERC721 token, uint tokenId, address owner, IERC20 tokenOut, uint amount) external payable {
    token.approve(to, tokenId);

    assembly {
      let result := call(gas(), to, 0, add(data, 0x20), mload(data), 0, 0)
      if eq(result, 0) {
        returndatacopy(0, 0, returndatasize())
        revert(0, returndatasize())
      }
    }

    // transfer the min token out to the owner
    tokenOut.transfer(owner, amount);

    // transfer remaining token balance to ADAPTER_OWNER
    tokenOut.transfer(address(ADAPTER_OWNER), tokenOut.balanceOf(address(this)));

  }

  function sellForTokenAndSwap(address to, bytes memory data, IERC721 tokenIn, uint tokenId, address owner, IERC20 bridgeToken, address toSwap, bytes memory dataSwap, IERC20 tokenOut, uint amount) external payable {
    tokenIn.approve(to, tokenId);

    assembly {
      let result := call(gas(), to, 0, add(data, 0x20), mload(data), 0, 0)
      if eq(result, 0) {
        returndatacopy(0, 0, returndatasize())
        revert(0, returndatasize())
      }
    }

    assembly {
      let result := call(gas(), toSwap, 0, add(dataSwap, 0x20), mload(dataSwap), 0, 0)
      if eq(result, 0) {
        returndatacopy(0, 0, returndatasize())
        revert(0, returndatasize())
      }
    }

    // transfer the min token out to the owner
    tokenOut.transfer(owner, amount);

    // transfer remaining token balance to ADAPTER_OWNER
    tokenOut.transfer(address(ADAPTER_OWNER), tokenOut.balanceOf(address(this)));

    // transfer remaining bridge token balance to ADAPTER_OWNER
    bridgeToken.transfer(address(ADAPTER_OWNER), bridgeToken.balanceOf(address(this)));
  }

  function sellForEth(address to, bytes memory data, IERC721 token, uint tokenId, address payable owner, uint amount) external payable {
    token.approve(to, tokenId);

    assembly {
      let result := call(gas(), to, 0, add(data, 0x20), mload(data), 0, 0)
      if eq(result, 0) {
        returndatacopy(0, 0, returndatasize())
        revert(0, returndatasize())
      }
    }
    uint wethBal = weth.balanceOf(address(this));
    weth.withdraw(wethBal);
    owner.transfer(amount);

    uint ethBalRemaining = wethBal - amount;
    ADAPTER_OWNER.transfer(ethBalRemaining);
  }
  
  function sellForTokenToWethToEth(address to, bytes memory data, IERC721 token, uint tokenId, address payable owner, address toSwap, bytes memory dataSwap, uint amount) external payable {
    token.approve(to, tokenId);

    assembly {
      let result := call(gas(), to, 0, add(data, 0x20), mload(data), 0, 0)
      if eq(result, 0) {
        returndatacopy(0, 0, returndatasize())
        revert(0, returndatasize())
      }
    }

    assembly {
      let result := call(gas(), toSwap, 0, add(dataSwap, 0x20), mload(dataSwap), 0, 0)
      if eq(result, 0) {
        returndatacopy(0, 0, returndatasize())
        revert(0, returndatasize())
      }
    }
    
    uint wethBal = weth.balanceOf(address(this));
    weth.withdraw(wethBal);
    owner.transfer(amount);
    
    uint ethBalRemaining = address(this).balance;
    ADAPTER_OWNER.transfer(ethBalRemaining);
  }

  function buyWithEth(address to, bytes memory data, uint amount, IERC721 token, uint tokenId, address owner) external payable {
    _executeAndTransfer(to, data, amount, token, tokenId, owner);
  }

  function buyWithWeth(address to, bytes memory data, uint amount, IERC721 token, uint tokenId, address owner) external {
    weth.withdraw(weth.balanceOf(address(this)));
    _executeAndTransfer(to, data, amount, token, tokenId, owner);
  }

  function buyWithToken(address router, IERC20 swapToken, bytes memory swapData, address to, bytes memory data, uint amount, IERC721 token, uint tokenId, address owner) external {
    _routerApproveMax(router, swapToken);

    assembly {
      let result := call(gas(), to, 0, add(swapData, 0x20), mload(swapData), 0, 0)
      if eq(result, 0) {
        returndatacopy(0, 0, returndatasize())
        revert(0, returndatasize())
      }
    }
    weth.withdraw(weth.balanceOf(address(this)));

    _executeAndTransfer(to, data, amount, token, tokenId, owner);

    uint swapTokenRemaining = swapToken.balanceOf(address(this));
    if (swapTokenRemaining > 0) {
      swapToken.transfer(ADAPTER_OWNER, swapTokenRemaining);
    }
  }

  function _executeAndTransfer (address to, bytes memory data, uint amount, IERC721 token, uint tokenId, address owner) internal {
    // CALL `to` with `data` with `amount` ETH. This call is expected to transfer the NFT to this contract
    assembly {
      let result := call(gas(), to, amount, add(data, 0x20), mload(data), 0, 0)
      if eq(result, 0) {
        returndatacopy(0, 0, returndatasize())
        revert(0, returndatasize())
      }
    }

    // transfer the NFT to the owner
    token.transferFrom(address(this), owner, tokenId);

    // transfer remaining ETH balance to ADAPTER_OWNER
    ADAPTER_OWNER.transfer(address(this).balance);
  }

  function _routerApproveMax(address router, IERC20 token) internal {
    if (token.allowance(address(this), router) < MAX_INT) {
      token.approve(router, MAX_INT);
    }
  }

  receive() external payable { }
}