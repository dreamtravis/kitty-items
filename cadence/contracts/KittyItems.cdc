import NonFungibleToken from "./NonFungibleToken.cdc"
import MetadataViews from "./MetadataViews.cdc"

pub contract KittyItems: NonFungibleToken {

    // Events
    //
    pub event ContractInitialized()
    pub event Withdraw(id: UInt64, from: Address?)
    pub event Deposit(id: UInt64, to: Address?)
    pub event Minted(id: UInt64, kind: UInt8, rarity: UInt8, index: UInt64)

    // Named Paths
    //
    pub let CollectionStoragePath: StoragePath
    pub let CollectionPublicPath: PublicPath
    pub let MinterStoragePath: StoragePath

    // totalSupply
    // The total number of KittyItems that have been minted
    //
    pub var totalSupply: UInt64

    pub enum Rarity: UInt8 {
        pub case legendary
        pub case epic
        pub case common
    }

    pub fun rarityToString(_ rarity: Rarity): String {
        switch rarity {
            case Rarity.legendary:
                return "Legendary"
            case Rarity.epic:
                return "Epic"
            case Rarity.common:
                return "Common"
        }

        return ""
    }

    pub enum Kind: UInt8 {
        pub case kiddo
    }

    pub fun kindToString(_ kind: Kind): String {
        switch kind {
            case Kind.kiddo:
                return "Kiddo"
        }

        return ""
    }

    access(self) var legendaryImagesArray: [String]
    access(self) var epicImagesArray: [String]
    access(self) var commonImagesArray: [String]

    // Mapping from rarity -> price
    //
    access(self) var itemRarityPriceMap: {Rarity: UFix64}

    // Return the initial sale price for an item of this rarity.
    //
    pub fun getItemPrice(rarity: Rarity): UFix64 {
        return self.itemRarityPriceMap[rarity]!
    }
    
    // A Kitty Item as an NFT
    //
    pub resource NFT: NonFungibleToken.INFT, MetadataViews.Resolver {

        pub let id: UInt64

        // The token kind (e.g. Fishbowl)
        pub let kind: Kind

        // The token rarity (e.g. Gold)
        pub let rarity: Rarity

        // The token index
        pub let index: UInt64

        init(id: UInt64, kind: Kind, rarity: Rarity, index: UInt64) {
            self.id = id
            self.kind = kind
            self.rarity = rarity
            self.index = index
        }

        pub fun name(): String {
            return KittyItems.rarityToString(self.rarity)
                .concat(" ")
                .concat(KittyItems.kindToString(self.kind))
        }

        pub fun description(): String {
            return "A "
                .concat(KittyItems.rarityToString(self.rarity).toLower())
                .concat(" ")
                .concat(KittyItems.kindToString(self.kind).toLower())
                .concat(" with serial number ")
                .concat(self.id.toString())
        }

        pub fun imageCID(): String {
            if( self.rarity == Rarity.legendary)
            {
                return KittyItems.legendaryImagesArray[self.index]
            }
            else if( self.rarity == Rarity.epic)
            {
                return KittyItems.epicImagesArray[self.index]
            }
            else if( self.rarity == Rarity.common)
            {
                return KittyItems.commonImagesArray[self.index]
            }
            return KittyItems.commonImagesArray[0]
        }

        pub fun getViews(): [Type] {
            return [
                Type<MetadataViews.Display>()
            ]
        }

        pub fun resolveView(_ view: Type): AnyStruct? {
            switch view {
                case Type<MetadataViews.Display>():
                    return MetadataViews.Display(
                        name: self.name(),
                        description: self.description(),
                        thumbnail: MetadataViews.IPFSFile(
                            cid: self.imageCID(), 
                            path: "sm.png"
                        )
                    )
            }

            return nil
        }
    }

    // This is the interface that users can cast their KittyItems Collection as
    // to allow others to deposit KittyItems into their Collection. It also allows for reading
    // the details of KittyItems in the Collection.
    pub resource interface KittyItemsCollectionPublic {
        pub fun deposit(token: @NonFungibleToken.NFT)
        pub fun getIDs(): [UInt64]
        pub fun borrowNFT(id: UInt64): &NonFungibleToken.NFT
        pub fun borrowKittyItem(id: UInt64): &KittyItems.NFT? {
            // If the result isn't nil, the id of the returned reference
            // should be the same as the argument to the function
            post {
                (result == nil) || (result?.id == id):
                    "Cannot borrow KittyItem reference: The ID of the returned reference is incorrect"
            }
        }
    }

    // Collection
    // A collection of KittyItem NFTs owned by an account
    //
    pub resource Collection: KittyItemsCollectionPublic, NonFungibleToken.Provider, NonFungibleToken.Receiver, NonFungibleToken.CollectionPublic {
        // dictionary of NFT conforming tokens
        // NFT is a resource type with an `UInt64` ID field
        //
        pub var ownedNFTs: @{UInt64: NonFungibleToken.NFT}

        // withdraw
        // Removes an NFT from the collection and moves it to the caller
        //
        pub fun withdraw(withdrawID: UInt64): @NonFungibleToken.NFT {
            let token <- self.ownedNFTs.remove(key: withdrawID) ?? panic("missing NFT")

            emit Withdraw(id: token.id, from: self.owner?.address)

            return <-token
        }

        // deposit
        // Takes a NFT and adds it to the collections dictionary
        // and adds the ID to the id array
        //
        pub fun deposit(token: @NonFungibleToken.NFT) {
            let token <- token as! @KittyItems.NFT

            let id: UInt64 = token.id

            // add the new token to the dictionary which removes the old one
            let oldToken <- self.ownedNFTs[id] <- token

            emit Deposit(id: id, to: self.owner?.address)

            destroy oldToken
        }

        // getIDs
        // Returns an array of the IDs that are in the collection
        //
        pub fun getIDs(): [UInt64] {
            return self.ownedNFTs.keys
        }

        // borrowNFT
        // Gets a reference to an NFT in the collection
        // so that the caller can read its metadata and call its methods
        //
        pub fun borrowNFT(id: UInt64): &NonFungibleToken.NFT {
            return &self.ownedNFTs[id] as &NonFungibleToken.NFT
        }

        // borrowKittyItem
        // Gets a reference to an NFT in the collection as a KittyItem,
        // exposing all of its fields (including the typeID & rarityID).
        // This is safe as there are no functions that can be called on the KittyItem.
        //
        pub fun borrowKittyItem(id: UInt64): &KittyItems.NFT? {
            if self.ownedNFTs[id] != nil {
                let ref = &self.ownedNFTs[id] as auth &NonFungibleToken.NFT
                return ref as! &KittyItems.NFT
            } else {
                return nil
            }
        }

        // destructor
        destroy() {
            destroy self.ownedNFTs
        }

        // initializer
        //
        init () {
            self.ownedNFTs <- {}
        }
    }

    // createEmptyCollection
    // public function that anyone can call to create a new empty collection
    //
    pub fun createEmptyCollection(): @NonFungibleToken.Collection {
        return <- create Collection()
    }

    // NFTMinter
    // Resource that an admin or something similar would own to be
    // able to mint new NFTs
    //
    pub resource NFTMinter {

        // mintNFT
        // Mints a new NFT with a new ID
        // and deposit it in the recipients collection using their collection reference
        //
        pub fun mintNFT(
            recipient: &{NonFungibleToken.CollectionPublic}, 
            kind: Kind, 
            rarity: Rarity,
            index: UInt64,
        ) {
            // deposit it in the recipient's account using their reference
            recipient.deposit(token: <-create KittyItems.NFT(id: KittyItems.totalSupply, kind: kind, rarity: rarity, index: index))

            emit Minted(
                id: KittyItems.totalSupply,
                kind: kind.rawValue,
                rarity: rarity.rawValue,
                index: index,
            )

            KittyItems.totalSupply = KittyItems.totalSupply + (1 as UInt64)
        }
    }

    // fetch
    // Get a reference to a KittyItem from an account's Collection, if available.
    // If an account does not have a KittyItems.Collection, panic.
    // If it has a collection but does not contain the itemID, return nil.
    // If it has a collection and that collection contains the itemID, return a reference to that.
    //
    pub fun fetch(_ from: Address, itemID: UInt64): &KittyItems.NFT? {
        let collection = getAccount(from)
            .getCapability(KittyItems.CollectionPublicPath)!
            .borrow<&KittyItems.Collection{KittyItems.KittyItemsCollectionPublic}>()
            ?? panic("Couldn't get collection")
        // We trust KittyItems.Collection.borowKittyItem to get the correct itemID
        // (it checks it before returning it).
        return collection.borrowKittyItem(id: itemID)
    }

    // initializer
    //
    init() {
        // set rarity price mapping
        self.itemRarityPriceMap = {
            Rarity.legendary: 125.0,
            Rarity.epic: 25.0,
            Rarity.common: 5.0
        }

        self.legendaryImagesArray = ["QmeY8inTQ8vTNu8z6Zk37GaprCMF2RYbnFNT9GWStDVsCK",
                                        "QmPCrDvqyCg2LoAcLmYnnKFwxA369CyjeDrzeunfHRgtDY",
                                        "QmV4PxrUk33tD5vfpZ2wKadAGK4UGNUBUqffXoXPfN3Diy",
                                        "QmR8Dz9opHbd1hECbqKkUsuRCBwvvbXt1XJaXZviuYHvo4",
                                        "QmWfWarjKpYGgycNAmmcVG2G2rTteofR7p1yrGASJLJpYK",
                                        "QmZLviN4pD256x9X7zmVad8CfS5qH2BkYjvSJbd8Bby3At",
                                        "QmWwNmJkomVgrrNnTQebTG3G8a47JNac6bD3KkpEqGEgni",
                                        "QmRpXC4ALMMSiMNUyrmCYgd3Df2SiAav44T8ePqrJHzpjZ",
                                        "QmQUSvaqXUa9uMDM5MLxHWH1N3vCNwTKiDQtURf4QJjgow",
                                        "QmSC8W2JXdX9V2CLD6NTPRSpBNnwmnbxkLitwm5gS8BUZM",
                                        "QmVDdgePc5aMFTX2F5ZDG7zSCrNG8S7AW4RVZVEAyaFMMJ",
                                        "Qmdn5Juk2Sk7k6ebLiEBKUS2tSJeAhEKUvfcke7Nrz3S4W",
                                        "QmNycmHCEW5AVqm45AEv4UKD4MvvKno9V5du2SetouNe1T",
                                        "QmRcveDQFrADzdeqZKpAMWQTuDPJ4RpPXRcZaoQKNNuV3K",
                                        "QmRPqEVWmN6qj293ZLfmqJ1jPv1k1n5RLDfPqyoP5jfMHT",
                                        "QmVkd8bQoCcZ8o9aUzZKZJ9uWxbDjJNVJT3wHpAUcfNBre",
                                        "QmSg3wq4puaKBcjBWrdjXst2WxikD9xQAvEGwAfmcKeQA7",
                                        "QmaJLA9HhM5yJzRKdqYKxwwJtvpeAdnwprj9onp9mEs4Mg",
                                        "QmWUAa97muL4oyK8E5ugrzudVgEArVTQufF4mUYc7SQBZ7",
                                        "QmeNq4LDCwUh6nYjxW3UhuDoauBNnngcW2xgHNaP63LBdT"]

        self.epicImagesArray = ["QmcoxJEmBTSjPWmtUciedHjMQie6eq33eAiRC6oSxbNJAM",
                                        "QmTCiX3RJ6e1385ZoJFtScfEzLwKT9nTh7qFTvAsuGrqVb",
                                        "Qmb75SFcWJi3Qd6FXofvsQFrukXvSU4jgrDyytfE9FjvnL",
                                        "QmSwqKez7aWh2WANWjz9LNa2gndMB566GRjji8STZ9qHSV",
                                        "QmeZUeSMSBHc6Lb9zEwGarJiAeAHaKGE6ryhnkGYCq4Zfm",
                                        "QmYk7XxbKSvHAFMeMg4JPPnDsUmNS4yzeemaDYuhPeJKpV",
                                        "QmVZJE2Vn7Eo7RJojnkWNfh5wJVdVq1PTtzMKV2ZFfyYET",
                                        "Qmf1dyZguNDo5qYW3URaqmXS1BECp4Cm9DNnFNquEjmN3e",
                                        "QmZa5rTRct8h5dsfiUQNiyoPZMGejqarPs5eY6HJ5FsiKQ",
                                        "QmRxeQ6bKKvLoEvJHWZNndQEGmwFAfmWdQrx8oRy9eXuat",
                                        "QmRvd9dQQg8NbrsokiYtRgPNjffNsivLGUEgahPoNXWBjX",
                                        "QmRqrLkvNREKqzjHfuxfWjwavmp86RiJDhVLcy5cgNWRx8",
                                        "QmVgnZEW8qHAJaVsAKJTNiWDjNKXsPd3bvjZKJWb6Gx9nX",
                                        "QmNgEdfimq3FA4TskC5iEAEWxr6GPMZZhSjRbcwJG33LmW",
                                        "QmdCBkbLkH6R1LwMapYAwNTZwiYxMV6AtfeTXyAjodK392",
                                        "QmSjDyWNSDEiv9JHPiepGMHisswjZN56KT9MHD6TT1PWWF",
                                        "QmNykhZTNpL8cWBqccGdz6omzxSEehHiCdru7oTeYQ9J7T",
                                        "QmSTptwvKqJxw32qA7R8VG44QMw7MR9bdRjKJbJf5r3fQo",
                                        "QmWNkP3tFZL48rAUNpzZbJ5WyrpxosedYVidTqhRLh3Aos",
                                        "QmXLdqMuSyfDirVFQNWTZih2h5Kkq2AQRhrrdW4UrFgCYq"]

        self.commonImagesArray = ["QmaSAMVNAjukHq1ieWLLmAWvwAxDrEfeb6Npj86ph9usTv",
                                        "QmShsoKPQcKBFL16uXoJT4yq5fyfVZ6tWJiGwCHVcb9Afq",
                                        "QmNvmZRZPc1onajGqtnMDi7X9Qs4wE9aSSD1X5kUvTtmvd",
                                        "QmTiK8kkMrrzRTUVeLXYkDznPkRPmy8AmDxCYDc6ZUPHfA",
                                        "QmS8JniXQni3NwmS3vXLvQ1cH2hvCBQRExaDrrJa7rybpp",
                                        "QmeYkfPSRVY2oYDyajDB5FWR4yoocHG1bG4zfqsav9MsAT",
                                        "QmNUnDsdJJBagFQQM9FTqR2kWi3fBNV8fDbwSQTB21NFjS",
                                        "QmRYHbY9DoDzaneANBP9kVNELdn49683XYgpRVSGBmgABC",
                                        "Qmao96a6EsaouFBjYBNECH7ydh4AiXFyqPBd79gVa3pgAS",
                                        "QmS47X1muUXTW8GzosGnyA3APtWi25cFUCHWfjKv17Eh9b",
                                        "QmexcM6aths16Fh4Dp2bzg7gBTjHV69vmP31TB8dKo1dGs",
                                        "QmS1YcTHMrsedvaszh2CCL8UfH4QNQ6rZ6QVGxqbPoMoeH",
                                        "QmUnMbB3gAC76cxeUNgx6Hig57ZGNXxTbxaU4JKb2RmWcD",
                                        "QmP4u7ZVrjUXZCANWq2Q3RooCnSjpbZhAnQmRbLxEkXRxR",
                                        "QmQ39egCZ74zMr38286DMTC2kRo7g9tozYtPoAG9j1iSMG",
                                        "QmXtVZdRrKF3qqRu8wyXpeDk7a2uASigtf4hqLzNr3xg5m",
                                        "QmcZzV3bzmYgsQYs2P6gUbDJuxxB3WHja33SgTVPESXA95",
                                        "QmRNRYksCwUtZVvLYkBHDnqYxVh29Mtk99N6XMLrwkfJx2",
                                        "QmSFQPQBrrVs6w2W2fRJw2RpdA41gKacfpXSHMNFcNdQjW",
                                        "QmcisFkvcCT9gm61mK1CqkEWvRFiczzCZDsKdvrbGfuMts"]

        // Set our named paths
        self.CollectionStoragePath = /storage/kittyItemsCollectionV10
        self.CollectionPublicPath = /public/kittyItemsCollectionV10
        self.MinterStoragePath = /storage/kittyItemsMinterV10

        // Initialize the total supply
        self.totalSupply = 0

        // Create a Minter resource and save it to storage
        let minter <- create NFTMinter()
        self.account.save(<-minter, to: self.MinterStoragePath)

        emit ContractInitialized()
    }
}
